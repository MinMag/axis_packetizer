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
    // Final CRC to present on the stream (apply final XOR before output)
    logic [31:0] crc_to_output;
    logic crc_clear;
    logic crc_hold;
    logic crc_update;

    logic [15:0] packet_len_q, packet_len_d;
    logic [15:0] packet_id_q, packet_id_d;
    logic header_pos_q, header_pos_d;

    logic [31:0] output_data_d;
    logic [31:0] input_data_q;
    logic output_data_tlast_d;
    logic output_data_tvalid_d;
    logic s_axis_tvalid_seen_q, s_axis_tvalid_seen_d;
    logic skip_payload_d, skip_payload_q;

    state_t control_state_d, control_state_q, control_state_qq;
    logic input_tvalid_q, input_tvalid_d;
    logic valid_capture;

    logic transfer_next_out;

    logic skid_ready;

    logic input_tlast_q;

    // Skid buffer internal signals
    logic        skid_out_tvalid_q, skid_out_tvalid_d;
    logic [31:0] skid_out_tdata_q, skid_out_tdata_d;
    logic        skid_out_tlast_q, skid_out_tlast_d;

    (* IOB="TRUE" *) logic [31:0] m_axis_tdata_q;
    (* IOB="TRUE" *) logic m_axis_tvalid_q;
    (* IOB="TRUE" *) logic m_axis_tlast_q;


    logic pipeline_stalled;

    logic s_axis_tready_q, s_axis_tready_d, s_axis_tready_q_internal;

    assign skid_ready = !skid_out_tvalid_q;

    assign M_AXIS_TDATA = m_axis_tdata_q;
    assign M_AXIS_TVALID = m_axis_tvalid_q;
    assign M_AXIS_TLAST = m_axis_tlast_q;

    assign S_AXIS_TREADY = s_axis_tready_q;

    assign pipeline_stalled = !M_AXIS_TREADY && (skid_out_tvalid_q || input_tvalid_q);

    always_ff @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            crc_value_q <= 32'hFFFFFFFF;
            control_state_q <= IDLE;
            s_axis_tvalid_seen_q <= '0;
            header_pos_q <= '0;
            packet_len_q <= '0;
            packet_id_q <= 16'b0;
            control_state_qq <= IDLE;
            skip_payload_q <= '0;
            input_tvalid_q <= '0;
            skid_out_tdata_q <= '0;
            skid_out_tvalid_q <= 1'b0;
            skid_out_tlast_q <= 1'b0; 
            s_axis_tready_q <= 1'b0;
            s_axis_tready_q_internal <= 1'b0;
        end else begin
            crc_value_q <= crc_value_d;
            control_state_q <= control_state_d;
            s_axis_tvalid_seen_q <= s_axis_tvalid_seen_d;
            header_pos_q <= header_pos_d;
            packet_len_q <= packet_len_d;
            packet_id_q <= packet_id_d;
            control_state_qq <= control_state_q;
            skip_payload_q <= skip_payload_d;
            input_tvalid_q <= input_tvalid_d;
            s_axis_tready_q <= s_axis_tready_d;
            s_axis_tready_q_internal <= s_axis_tready_d;
            if (M_AXIS_TREADY) begin
                if(skid_out_tvalid_q) begin
                    m_axis_tdata_q <= skid_out_tdata_q;
                    m_axis_tvalid_q <= 1'b1;
                    m_axis_tlast_q <= skid_out_tlast_q;
                    skid_out_tvalid_q <= 1'b0;
                end else begin
                    m_axis_tdata_q <= output_data_d;
                    m_axis_tvalid_q <= output_data_tvalid_d;
                    m_axis_tlast_q <= output_data_tlast_d;
                end
            end else begin
                if (!skid_out_tvalid_q && output_data_tvalid_d) begin
                    skid_out_tdata_q <= output_data_d;
                    skid_out_tvalid_q <= 1'b1;
                    skid_out_tlast_q <= output_data_tlast_d;
                end
            end
        end
    end

    always_ff @(posedge CLK) begin
        // Clock Enable: Only capture data when a valid slave handshake occurs.
        // This prevents random toggling on the input wires from propagating 
        // into your internal logic, saving dynamic power.
        if (S_AXIS_TVALID && S_AXIS_TREADY) begin
            input_data_q <= S_AXIS_TDATA;
            input_tlast_q <= S_AXIS_TLAST;
        end
    end

    assign valid_capture = S_AXIS_TVALID && S_AXIS_TREADY;

    always_comb begin

        control_state_d = control_state_q;

        s_axis_tready_d = 1'b0; // only set in specific states
        packet_id_d = packet_id_q;
        header_pos_d = header_pos_q;
        output_data_d = '0;
        packet_len_d = packet_len_q;
        output_data_tlast_d = '0; // Qs or zeros?
        output_data_tvalid_d = '0;
        crc_clear = 1'b0;
        crc_hold = 1'b0;
        crc_update = 1'b0;
        input_tvalid_d = input_tvalid_q;
        skip_payload_d = skip_payload_q;
        if (control_state_q[IDLE_IDX]) begin
            s_axis_tready_d = 1'b1;
            if (S_AXIS_TVALID) begin
                packet_len_d = S_PAYLOAD_LEN;
                control_state_d = WRITE_HEADER;
                input_tvalid_d = '1; //mark input_tdata as valid non-transmitted data
                s_axis_tready_d = 1'b0;
            end
        end else if (control_state_q[WRITE_HEADER_IDX]) begin
            s_axis_tready_d = 1'b0; //Hold off accepting more data while header is written
            output_data_tvalid_d = 1'b1; //This state will always have data ready?
            case (header_pos_q)
                1'b0: begin
                    output_data_d = {16'h63df, packet_id_q};
                    if (skid_ready) begin
                        header_pos_d = 1'b1;
                    end
                end
                1'b1: begin
                    output_data_d = {packet_len_q, 16'h0};
                    if (skid_ready) begin
                        header_pos_d = 1'b0;
                        control_state_d = skip_payload_q ? WRITE_CRC : STREAM_PAYLOAD;
                        s_axis_tready_d = !pipeline_stalled;
                    end
                end
                default: begin
                    output_data_d = '0;
                end
            endcase
        end else if (control_state_q[STREAM_PAYLOAD_IDX]) begin
            // Does below properly time tvalid s.t. data comes to a stop correctly if s_axis_tvalid drops in this state?
            // I don't think it does because TVALID could be high but we don't accept the data until s_axis_tready is high?
            // We need to set tvalid as high on first entrance always because 
            // input data will be valid if 
            //TODO: maybe break the input data signals into a fifo-like structure...
            output_data_d = input_data_q;
            output_data_tvalid_d = input_tvalid_q;
            output_data_tlast_d = 1'b0;
            if (skid_ready || !input_tvalid_q) begin
                input_tvalid_d = valid_capture;
            end
            // If downstream can't accept data, we can't replace current data with new data => drop s_axis_tready_d.
            // Don't be ready once we are exiting payload, since next data will need to come into idle
            // TODO: We could potentially start next transistion here and skip IDLE, move directly to write_header
            if (pipeline_stalled) begin
                s_axis_tready_d = 1'b0;
            end else if (input_tvalid_q && input_tlast_q) begin
                s_axis_tready_d = 1'b0;
            end else begin
                s_axis_tready_d = 1'b1;
            end
            // Only update CRC on an accepted payload beat
            crc_update = skid_ready && input_tvalid_q;
            // Mark that the last payload beat was accepted by the slave
            if(input_tvalid_q && input_tlast_q && skid_ready) begin
                control_state_d  = WRITE_CRC;
            end
        end else if (control_state_q[WRITE_CRC_IDX]) begin
            // Present CRC-32 on the stream: apply final XOR (0xFFFFFFFF)
            crc_to_output = ~crc_value_q;
            output_data_d = crc_to_output;
            output_data_tvalid_d = 1'b1;
            // Only assert TLAST when the CRC beat will actually be transferred
            output_data_tlast_d = 1'b1;
            crc_hold = 1'b1;
            // In WRITE_CRC, data pipeline must necessarily be empty, so would be ready to accept new data?
            // No, because if skid_ready is low, could still fill up pipeline.
            s_axis_tready_d = 1'b0; // 1'b0 for now to not miss the IDLE exit transition, but should be made more robust
            if (skid_ready) begin //Final data transfer
                crc_hold = 1'b0;
                control_state_d = input_tvalid_q ? WRITE_HEADER : IDLE;
                crc_clear = 1'b1;
                packet_id_d = packet_id_q + 1'b1;
                s_axis_tready_d = !input_tvalid_q;
            end
        end
        s_axis_tvalid_seen_d = S_AXIS_TVALID && s_axis_tready_d; //should be S_AXIS_TVALID or s_axis_tvalid_seen_q?
        if (crc_clear) begin
            crc_value_d = 32'hFFFFFFFF;
        end else if (crc_hold) begin
            crc_value_d = crc_value_q;
        end else if (crc_update) begin
            crc_value_d = crc_out;
        end else begin
            // No update: hold current value
            crc_value_d = crc_value_q;
        end

    end

    crc32_parallel crc (
        .crcIn(crc_value_q),
        .crcOut(crc_out),
        .data(input_data_q)
    );

    assign M_AXIS_TKEEP = {KEEP_WIDTH{1'b1}};

endmodule
