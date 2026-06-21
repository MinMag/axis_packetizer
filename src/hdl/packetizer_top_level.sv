`timescale 1ns / 1ps

module packetizer_top_level #(
    parameter int P_DATA_WIDTH = 32
)(
    // --- Base Clocks & Resets ---
    input  logic                      CLK,            // 125 MHz Base Oscillator
    input  logic                      REF_CLK_300MHZ, // 300 MHz for IDELAYCTRL
    input  logic                      RST_N,          // Asynchronous Active-Low Reset

    // --- Ingress AXI-Stream (Clocked by CLK) ---
    input  logic [P_DATA_WIDTH-1:0]   S_AXIS_TDATA,
    input  logic [(P_DATA_WIDTH/8)-1:0] S_AXIS_TKEEP,
    input  logic                      S_AXIS_TVALID,
    output logic                      S_AXIS_TREADY,
    input  logic                      S_AXIS_TLAST,
    
    // --- Control Inputs ---
    input  logic [15:0]               S_PAYLOAD_LEN,

    // --- Egress AXI-Stream (Source-Synchronous to M_AXIS_ACLK) ---
    output logic [P_DATA_WIDTH-1:0]   M_AXIS_TDATA,
    output logic [(P_DATA_WIDTH/8)-1:0] M_AXIS_TKEEP,
    output logic                      M_AXIS_TVALID,
    input  logic                      M_AXIS_TREADY,
    output logic                      M_AXIS_TLAST,
    output logic                      M_AXIS_ACLK     // Forwarded 125 MHz Clock
);

    // =========================================================================
    // 1. Internal Net Declarations
    // =========================================================================

    logic idelay_rdy;
    logic system_rst_n;
    logic reset_req;
    logic [1:0] rst_sync_reg;

    // Internal nets bridging the pure logic core to the physical ODELAYs
    logic [P_DATA_WIDTH-1:0]     m_axis_tdata_int;
    logic [(P_DATA_WIDTH/8)-1:0] m_axis_tkeep_int;
    logic                        m_axis_tvalid_int;
    logic                        m_axis_tlast_int;

    // =========================================================================
    // 2. Clock Management (MMCM)
    // =========================================================================
    // Generates the 0-degree CLK and 180-degree CLK

    // =========================================================================
    // 3. I/O Delay Calibration
    // =========================================================================
    // Calibrates all ODELAYE3 primitives in this I/O bank
    IDELAYCTRL #(
        .SIM_DEVICE("ULTRASCALE")
    ) i_idelayctrl (
        .RDY    (idelay_rdy),
        .REFCLK (REF_CLK_300MHZ),
        .RST    (~RST_N) // IDELAYCTRL reset is active-high
    );

    // =========================================================================
    // 4. Safe Reset Synchronizer
    // =========================================================================
    // The core logic must not come out of reset until the clock is stable AND 
    // the output delay pads are fully calibrated.
    assign reset_req = ~(RST_N & idelay_rdy);

    always_ff @(posedge CLK or posedge reset_req) begin
        if (reset_req) begin
            rst_sync_reg <= 2'b00;
        end else begin
            // Shift in 1's to safely release reset synchronously
            rst_sync_reg <= {rst_sync_reg[0], 1'b1}; 
        end
    end
    assign system_rst_n = rst_sync_reg[1];

    // =========================================================================
    // 5. Logical Core Instantiation (Tier 1)
    // =========================================================================
    axis_packetizer #(
        .P_DATA_WIDTH(P_DATA_WIDTH)
    ) packetizer_core_inst (
        .CLK           (CLK),
        .RST_N         (system_rst_n),

        // Ingress
        .S_AXIS_TDATA  (S_AXIS_TDATA),
        .S_AXIS_TKEEP  (S_AXIS_TKEEP),
        .S_AXIS_TVALID (S_AXIS_TVALID),
        .S_AXIS_TREADY (S_AXIS_TREADY),
        .S_AXIS_TLAST  (S_AXIS_TLAST),

        // Control
        .S_PAYLOAD_LEN (S_PAYLOAD_LEN),

        // Egress (Routes to ODELAYs, not directly to pins)
        .M_AXIS_TDATA  (m_axis_tdata_int),
        .M_AXIS_TKEEP  (m_axis_tkeep_int),
        .M_AXIS_TVALID (m_axis_tvalid_int),
        .M_AXIS_TREADY (M_AXIS_TREADY), // TREADY comes directly from the pin
        .M_AXIS_TLAST  (m_axis_tlast_int)
    );

    // =========================================================================
    // 6. Source-Synchronous Clock Forwarding
    // =========================================================================
    // Forwards CLK directly to the physical output pad
    ODDRE1 #(
        .IS_C_INVERTED(1'b0),
        .SRVAL(1'b0)
    ) clk_fwd_inst (
        .Q  (M_AXIS_ACLK),
        .C  (CLK),
        .D1 (1'b1), // High on rising edge
        .D2 (1'b0), // Low on falling edge
        .SR (~system_rst_n)
    );

    // =========================================================================
    // 7. Output Delay Injection (Surgical Hold Fix)
    // =========================================================================
    // Injects exactly 800ps of physical delay to the data lines to meet 
    // the downstream ASIC's hold requirements without sacrificing setup time.
    
    genvar i;
    generate
        // Delay TDATA
        for (i = 0; i < P_DATA_WIDTH; i++) begin : gen_odelay_tdata
            ODELAYE3 #(
                .DELAY_TYPE("FIXED"),
                .DELAY_VALUE(800),            
                .REFCLK_FREQUENCY(300.0),
                .DELAY_FORMAT("TIME"),         
                .SIM_DEVICE("ULTRASCALE_PLUS")
            ) i_odelay_tdata (
                .CASC_OUT(), .CNTVALUEOUT(), .CASC_IN(1'b0), .CASC_RETURN(1'b0),
                .CE(1'b0), .CLK(1'b0), .CNTVALUEIN(9'b0), .EN_VTC(1'b1), .INC(1'b0), .LOAD(1'b0), .RST(1'b0),
                .ODATAIN(m_axis_tdata_int[i]), 
                .DATAOUT(M_AXIS_TDATA[i])    
            );
        end

        // Delay TKEEP
        for (i = 0; i < (P_DATA_WIDTH/8); i++) begin : gen_odelay_tkeep
            ODELAYE3 #(
                .DELAY_TYPE("FIXED"),
                .DELAY_VALUE(800),            
                .REFCLK_FREQUENCY(300.0),
                .DELAY_FORMAT("TIME"),         
                .SIM_DEVICE("ULTRASCALE_PLUS")         
            ) i_odelay_tkeep (
                .CASC_OUT(), .CNTVALUEOUT(), .CASC_IN(1'b0), .CASC_RETURN(1'b0),
                .CE(1'b0), .CLK(1'b0), .CNTVALUEIN(9'b0), .EN_VTC(1'b1), .INC(1'b0), .LOAD(1'b0), .RST(1'b0),
                .ODATAIN(m_axis_tkeep_int[i]), 
                .DATAOUT(M_AXIS_TKEEP[i])    
            );
        end
    endgenerate

    // Delay TVALID
    ODELAYE3 #(
        .DELAY_TYPE("FIXED"),
        .DELAY_VALUE(800),            
        .REFCLK_FREQUENCY(300.0),
        .DELAY_FORMAT("TIME"),         
                .SIM_DEVICE("ULTRASCALE_PLUS")         
    ) i_odelay_tvalid (
        .CASC_OUT(), .CNTVALUEOUT(), .CASC_IN(1'b0), .CASC_RETURN(1'b0),
        .CE(1'b0), .CLK(1'b0), .CNTVALUEIN(9'b0), .EN_VTC(1'b1), .INC(1'b0), .LOAD(1'b0), .RST(1'b0),
        .ODATAIN(m_axis_tvalid_int), 
        .DATAOUT(M_AXIS_TVALID)    
    );

    // Delay TLAST
    ODELAYE3 #(
        .DELAY_TYPE("FIXED"),
        .DELAY_VALUE(800),            
        .REFCLK_FREQUENCY(300.0),
        .DELAY_FORMAT("TIME"),         
        .SIM_DEVICE("ULTRASCALE_PLUS")         
    ) i_odelay_tlast (
        .CASC_OUT(), .CNTVALUEOUT(), .CASC_IN(1'b0), .CASC_RETURN(1'b0),
        .CE(1'b0), .CLK(1'b0), .CNTVALUEIN(9'b0), .EN_VTC(1'b1), .INC(1'b0), .LOAD(1'b0), .RST(1'b0),
        .ODATAIN(m_axis_tlast_int), 
        .DATAOUT(M_AXIS_TLAST)    
    );

endmodule