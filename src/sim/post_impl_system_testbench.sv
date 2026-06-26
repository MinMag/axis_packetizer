`timescale 1ps / 1ps

module tb_packetizer_system_top;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter int P_DATA_WIDTH = 32;
    parameter int KEEP_WIDTH   = P_DATA_WIDTH/8;

    // =========================================================================
    // Signals
    // =========================================================================
    // Clocks and Resets
    logic CLK = 0;
    logic REF_CLK_300MHZ = 0;
    logic RST_N = 0;

    // AXI-Stream Ingress (Driven by Testbench)
    logic [P_DATA_WIDTH-1:0] S_AXIS_TDATA = '0;
    logic [KEEP_WIDTH-1:0]   S_AXIS_TKEEP = '0;
    logic                    S_AXIS_TVALID = 0;
    wire                     S_AXIS_TREADY;
    logic                    S_AXIS_TLAST = 0;

    // Control
    logic [15:0]             S_PAYLOAD_LEN = '0;

    // AXI-Stream Egress (Monitored by Testbench)
    wire [P_DATA_WIDTH-1:0]  M_AXIS_TDATA;
    wire [KEEP_WIDTH-1:0]    M_AXIS_TKEEP;
    wire                     M_AXIS_TVALID;
    logic                    M_AXIS_TREADY = 1; // Always ready by default
    wire                     M_AXIS_TLAST;
    wire                     M_AXIS_ACLK;

    // =========================================================================
    // Device Under Test (DUT)
    // =========================================================================
    packetizer_top_level #(
        .P_DATA_WIDTH(P_DATA_WIDTH)
    ) dut (
        .CLK(CLK),
        .REF_CLK_300MHZ(REF_CLK_300MHZ),
        .RST_N(RST_N),
        
        .S_AXIS_TDATA(S_AXIS_TDATA),
        .S_AXIS_TKEEP(S_AXIS_TKEEP),
        .S_AXIS_TVALID(S_AXIS_TVALID),
        .S_AXIS_TREADY(S_AXIS_TREADY),
        .S_AXIS_TLAST(S_AXIS_TLAST),
        
        .S_PAYLOAD_LEN(S_PAYLOAD_LEN),
        
        .M_AXIS_TDATA(M_AXIS_TDATA),
        .M_AXIS_TKEEP(M_AXIS_TKEEP),
        .M_AXIS_TVALID(M_AXIS_TVALID),
        .M_AXIS_TREADY(M_AXIS_TREADY),
        .M_AXIS_TLAST(M_AXIS_TLAST),
        .M_AXIS_ACLK(M_AXIS_ACLK)
    );

    // =========================================================================
    // Clock Generation
    // =========================================================================
    // 125 MHz Base Clock (8.000 ns period = 8000 ps)
    always #4000 CLK = ~CLK;

    // 300 MHz Reference Clock (3.333 ns period = 3333 ps)
    always begin
        #1666 REF_CLK_300MHZ = ~REF_CLK_300MHZ;
        #1667 REF_CLK_300MHZ = ~REF_CLK_300MHZ;
    end

    // =========================================================================
    // Tasks
    // =========================================================================
    task send_packet(input int length_bytes);
        int num_beats;
        int i;
        logic [P_DATA_WIDTH-1:0] test_data;
        
        num_beats = (length_bytes + KEEP_WIDTH - 1) / KEEP_WIDTH;
        test_data = 32'hDEADBEEF;

        // Drive signals on FALLING EDGE
        // and avoid zero-delay testbench race conditions against physical models.
        @(negedge CLK);
        S_PAYLOAD_LEN <= length_bytes[15:0];
        
        for (i = 0; i < num_beats; i++) begin
            @(negedge CLK);
            S_AXIS_TVALID <= 1'b1;
            S_AXIS_TDATA  <= test_data + i; 
            
            // Handle last beat and TKEEP
            if (i == num_beats - 1) begin
                S_AXIS_TLAST <= 1'b1;
                // Calculate TKEEP for final beat
                if (length_bytes % KEEP_WIDTH == 0)
                    S_AXIS_TKEEP <= {KEEP_WIDTH{1'b1}};
                else
                    S_AXIS_TKEEP <= (1 << (length_bytes % KEEP_WIDTH)) - 1;
            end else begin
                S_AXIS_TLAST <= 1'b0;
                S_AXIS_TKEEP <= {KEEP_WIDTH{1'b1}};
            end
            
            // Wait for handshake
            @(posedge CLK);
            while (S_AXIS_TREADY !== 1'b1) begin
                @(posedge CLK);
            end
        end
        
        // Clear bus
        @(negedge CLK);
        S_AXIS_TVALID <= 1'b0;
        S_AXIS_TLAST  <= 1'b0;
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("Starting Post-Implementation Verification...");

        // Initialize and hold reset
        RST_N = 0;
        S_AXIS_TVALID = 0;
        M_AXIS_TREADY = 1;
        
        // Wait 1 us in reset
        #1000000; 
        
        // Release Reset
        @(negedge CLK);
        RST_N = 1;
        $display("[%0t ps] Reset Released.", $time);

        //Wait for IDELAYCTRL calibration. 
        $display("[%0t ps] Waiting 15us for IDELAYCTRL to calibrate...", $time);
        #15000000; 
        
        // Send a normal 16-byte packet
        $display("[%0t ps] Sending 16-byte packet...", $time);
        send_packet(16);
        
        // Send a non-aligned 15-byte packet
        #20000; // Small idle gap
        $display("[%0t ps] Sending 15-byte packet...", $time);
        send_packet(15);
        
        // Send back-to-back packets (zero cycle gap)
        #20000;
        $display("[%0t ps] Sending back-to-back stress test...", $time);
        send_packet(8);
        send_packet(12);

        // Wait for pipeline to drain completely out physical pins
        #100000;
        
        $display("[%0t ps] Simulation Complete.", $time);
        $finish;
    end

endmodule
