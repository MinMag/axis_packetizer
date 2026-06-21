`timescale 1ns / 1ps

module packetizer_system_top #(
    parameter int P_DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = P_DATA_WIDTH/8
)(
    input  logic                    CLK,      // Raw 125 MHz from board
    input  logic                    RST_N,    // External active-low reset

    // AXI-Stream Ingress (Driven by clk_core)
    input  logic [P_DATA_WIDTH-1:0] S_AXIS_TDATA,
    input  logic [KEEP_WIDTH-1:0]   S_AXIS_TKEEP,
    input  logic                    S_AXIS_TVALID,
    output logic                    S_AXIS_TREADY,
    input  logic                    S_AXIS_TLAST,

    // AXI-Stream Egress (Source-Synchronous Output)
    output logic [P_DATA_WIDTH-1:0] M_AXIS_TDATA,
    output logic [KEEP_WIDTH-1:0]   M_AXIS_TKEEP,
    output logic                    M_AXIS_TVALID,
    input  logic                    M_AXIS_TREADY,
    output logic                    M_AXIS_TLAST,
    output logic                    M_AXIS_ACLK,

    input  logic [15:0]             S_PAYLOAD_LEN
);

    // --- Internal Nets ---
    logic clk_core;
    logic clk_io;
    logic mmcm_locked;
    logic system_rst_n;
    logic idly_ready;
    logic ref_clk_300mhz;

    // --- 1. Clock Management ---
    clk_wiz_0 clk_manager_inst (
        .clk_in1  (CLK),
        .CLK_CORE (clk_core),
        .CLK_IO   (clk_io),
        .ref_clk_300mhz(ref_clk_300mhz),
        .reset    (~RST_N),
        .locked   (mmcm_locked)
    );

    assign system_rst_n = RST_N & mmcm_locked & idly_ready;

    // --- 2. The Core Packetizer Logic ---
    // Notice we pass clk_core and system_rst_n here!
    axis_packetizer #(
        .P_DATA_WIDTH(P_DATA_WIDTH)
    ) packetizer_core_inst (
        .CLK           (clk_core),     
        .RST_N         (system_rst_n), 
        
        // Ingress Ports
        .S_AXIS_TDATA  (S_AXIS_TDATA),
        .S_AXIS_TKEEP  (S_AXIS_TKEEP),
        .S_AXIS_TVALID (S_AXIS_TVALID),
        .S_AXIS_TREADY (S_AXIS_TREADY),
        .S_AXIS_TLAST  (S_AXIS_TLAST),
        
        // Egress Ports
        .M_AXIS_TDATA  (M_AXIS_TDATA_internal),
        .M_AXIS_TKEEP  (M_AXIS_TKEEP),
        .M_AXIS_TVALID (M_AXIS_TVALID),
        .M_AXIS_TREADY (M_AXIS_TREADY),
        .M_AXIS_TLAST  (M_AXIS_TLAST),
        
        .S_PAYLOAD_LEN (S_PAYLOAD_LEN)
    );

IDELAYCTRL i_idelayctrl (
    .RDY(idly_ready),
    .REFCLK(ref_clk_300mhz), // Needs a stable 300MHz clock
    .RST(~system_rst_n)
);

// Example for one bit of TDATA
// assign M_AXIS_TDATA = tdata_delayed;
    wire [31:0] tdata_delayed;
    wire [31:0] M_AXIS_TDATA_internal;
generate
    genvar i;
    for (i=0; i < 32; i++) begin : gen_odelay
    ODELAYE3 #(
        .DELAY_TYPE("FIXED"),         // Fixed delay for board-level skew compensation
        .DELAY_VALUE(1250),            // Delay in ps (250ps = 0.25ns)
        .REFCLK_FREQUENCY(300.0),      // Frequency of your IDELAYCTRL reference clock
        .DELAY_FORMAT("TIME")
    ) i_tdata_delay (
        .CNTVALUEOUT(),
        .DATAOUT(M_AXIS_TDATA[i]),      // Routed to the output port
        .CASC_IN(1'b0),
        .CASC_RETURN(1'b0),
        .CE(1'b0),
        .CLK(1'b0),
        .CNTVALUEIN(9'b0),
        .ODATAIN(M_AXIS_TDATA_internal[i]), // From your m_axis_tdata_q_reg
        .EN_VTC(1'b1),
        .INC(1'b0),
        .LOAD(1'b0),
        .RST(1'b0)
    );
    end

endgenerate
    // --- 3. The Physical I/O Clock Forwarder ---
    // Remove this from axis_packetizer.sv and put it here.
    ODDRE1 #(
        .SIM_DEVICE("ULTRASCALE_PLUS")
    ) rx_clk_forward_inst (
        .Q  (M_AXIS_ACLK),  
        .C  (clk_io),       // Driven by the 90-degree shifted clock
        .D1 (1'b1),         
        .D2 (1'b0),         
        .SR (1'b0)          
    );

endmodule