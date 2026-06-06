`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 06/06/2026 12:36:46 AM
// Design Name:
// Module Name: axis_packetizer
// Project Name:
// Target Devices
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module axis_packetizer #(
    parameter int P_DATA_WIDTH = 32,
    parameter int KEEP_WIDTH = P_DATA_WIDTH/8
)(
    input  logic                  CLK,
    input  logic                  RST_N,

    //AXI-Stream Ingress
    input  logic [P_DATA_WIDTH-1:0] S_AXIS_TDATA,
    input  logic [KEEP_WIDTH-1:0] S_AXIS_TKEEP,
    input  logic                  S_AXIS_TVALID,
    output logic                  S_AXIS_TREADY,
    input  logic                  S_AXIS_TLAST,

    //AXI-Stream Egress
    output logic [P_DATA_WIDTH-1:0] M_AXIS_TDATA,
    output logic [KEEP_WIDTH-1:0] M_AXIS_TKEEP,
    output logic                  M_AXIS_TVALID,
    input  logic                  M_AXIS_TREADY,
    output logic                  M_AXIS_TLAST,

    //Implementation Specific Signals
    input  logic [15:0]           S_PAYLOAD_LEN
);

    typedef enum logic [3:0] {
        IDLE = 4'b0001,
        WRITE_HEADER = 4'b0010,
        STREAM_PAYLOAD = 4'b0100,
        WRITE_CRC = 4'b1000
     } state_t;

    // State index enum: use these to index into the one-hot `state_t` vector
    typedef enum int {
        IDLE_IDX = 0,
        WRITE_HEADER_IDX = 1,
        STREAM_PAYLOAD_IDX = 2,
        WRITE_CRC_IDX = 3
    } state_idx_t;

    logic [31:0] crc_value_q, crc_value_d;
    logic [31:0] crc_out;
    logic crc_clear;

    logic [31:0] output_data_q, output_data_d;
    logic [31:0] input_data_q;
    logic output_data_tlast_q, output_data_tlast_d;
    logic output_data_tvalid_q, output_data_tvalid_d;
    logic s_axis_tvalid_seen_q, s_axis_tvalid_seen_d;

    state_t control_state_d, control_state_q;


    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_value_q <= 32'hFFFFFFFF;
            control_state_q <= IDLE;
            output_data_tvalid_q <= '0;
            output_data_tlast_q <= '0;
            s_axis_tvalid_seen_q <= '0;
        end else begin
            crc_value_q <= crc_value_d;
            control_state_q <= control_state_d;
            output_data_tvalid_q <= output_data_tvalid_d;
            output_data_tlast_q <= output_data_tlast_d;
            s_axis_tvalid_seen_q <= s_axis_tvalid_seen_d;
        end
    end

    always_ff @(posedge clk) begin
        // Only capture new data when the downstream bus is moving (no data stall)
        if (M_AXIS_TREADY) begin
            output_data_q <= output_data_d;
        end
    end

    always_ff @(posedge clk) begin
        // Clock Enable: Only capture data when a valid slave handshake occurs.
        // This prevents random toggling on the input wires from propagating 
        // into your internal logic, saving dynamic power.
        if (S_AXIS_TVALID && S_AXIS_TREADY) begin
            input_data_q <= S_AXIS_TDATA;
        end
    end

    always_comb begin
        crc_value_d = crc_out;
        control_state_d = control_state_q;
        s_axis_tvalid_seen_d = s_axis_tvalid_seen_q;
        if (crc_clear) begin
            crc_value_d = 32'hFFFFFFFF;
        end
        if (control_state_q[IDLE_IDX]) begin
            S_AXIS_TREADY = 1'b1;
            if (S_AXIS_TVALID) begin
                s_axis_tvalid_seen_d = 1'b1;
                control_state_d = WRITE_HEADER;
            end
        end else if (control_state_q[WRITE_HEADER_IDX]) begin
            
        end else if (control_state_q[STREAM_PAYLOAD_IDX]) begin
            
        end else if (control_state_q[WRITE_CRC_IDX]) begin
            
        end

    end

    crc32_parallel crc (
        .crcIn(crc_value_q),
        .crcOut(crc_out),
        .data('0)
    );

    assign M_AXIS_TLAST = output_data_tlast_q;
    assign M_AXIS_TVALID = output_data_tvalid_q;
    assign M_AXIS_TDATA = output_data_q;

endmodule
