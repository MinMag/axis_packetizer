module xpm_fifo_axis #(
    /* verilator lint_off UNUSEDPARAM */
        parameter CLOCKING_MODE,
        parameter FIFO_DEPTH,
        parameter FIFO_MEMORY_TYPE,
        parameter PACKET_FIFO,
        parameter USE_ADV_FEATURES
    /* verilator lint_on UNUSEDPARAM */
    )  (
        // Write Side (250 MHz Core Domain)
        input s_aclk        ,
        input s_aresetn     ,
        input [31:0] s_axis_tdata  ,
        input s_axis_tvalid ,
        input s_axis_tlast  ,
        output s_axis_tready ,      // Feeds back into your FSM

        // Read Side (125 MHz I/O Domain)
        input  m_aclk        ,
        output [31:0] m_axis_tdata  ,
        output m_axis_tvalid ,
        output m_axis_tlast  ,
        input  m_axis_tready        // Driven by your IOB boundary
    );

    assign m_axis_tdata = s_axis_tdata;
    assign m_axis_tvalid = s_axis_tvalid;
    assign m_axis_tlast = s_axis_tlast;
    assign s_axis_tready = m_axis_tready;

endmodule
