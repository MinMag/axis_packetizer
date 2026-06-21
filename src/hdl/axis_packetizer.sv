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
    output logic                  M_AXIS_ACLK,

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
    logic exit_payload_d, exit_payload_q;
    logic input_tvalid_q, input_tvalid_d;
    logic valid_capture;

    logic transfer_next_out;

    logic skid_ready;

    logic [31:0] out_tdata_q;
    logic        out_tvalid_q;
    logic        out_tlast_q;
    // Skid buffer internal signals
    logic        skid_out_tvalid_q, skid_out_tvalid_d;
    logic [31:0] skid_out_tdata_q, skid_out_tdata_d;
    logic        skid_out_tlast_q, skid_out_tlast_d;


    logic [31:0] next_io_tdata;
    logic        next_io_tvalid;
    logic        next_io_tlast;

    assign skid_ready = !skid_out_tvalid_q;

    always_ff @(posedge CLK or negedge RST_N) begin
        if (!RST_N) begin
            crc_value_q <= 32'hFFFFFFFF;
            control_state_q <= IDLE;
            s_axis_tvalid_seen_q <= '0;
            header_pos_q <= '0;
            packet_len_q <= '0;
            packet_id_q <= 16'b0;
            exit_payload_q <= 1'b0;
            control_state_qq <= IDLE;
            skip_payload_q <= '0;
            input_tvalid_q <= '0;
            out_tdata_q <= '0; // Do I need to reset all of these? Or do  Inot reset data flops
            out_tvalid_q <= 1'b0;
            out_tlast_q <= 1'b0;
            skid_out_tdata_q <= '0;
            skid_out_tvalid_q <= 1'b0;
            skid_out_tlast_q <= 1'b0; 
        end else begin
            crc_value_q <= crc_value_d;
            control_state_q <= control_state_d;
            s_axis_tvalid_seen_q <= s_axis_tvalid_seen_d;
            header_pos_q <= header_pos_d;
            packet_len_q <= packet_len_d;
            packet_id_q <= packet_id_d;
            exit_payload_q <= exit_payload_d;
            control_state_qq <= control_state_q;
            skip_payload_q <= skip_payload_d;
            input_tvalid_q <= input_tvalid_d;
            out_tdata_q <= next_io_tdata;
            out_tvalid_q <= next_io_tvalid;
            out_tlast_q <= next_io_tlast;
            skid_out_tdata_q <= skid_out_tdata_d;
            skid_out_tvalid_q <= skid_out_tvalid_d;
            skid_out_tlast_q <= skid_out_tlast_d;
        end
    end

    // always_ff @(posedge CLK) begin
    //     // Only capture new output data when the downstream accepts it
    //     if (1) begin
    //         output_data_q <= output_data_d;
    //     end
    // end

    always_ff @(posedge CLK) begin
        // Clock Enable: Only capture data when a valid slave handshake occurs.
        // This prevents random toggling on the input wires from propagating 
        // into your internal logic, saving dynamic power.
        if (S_AXIS_TVALID && S_AXIS_TREADY) begin
            input_data_q <= S_AXIS_TDATA;
        end
    end

    assign valid_capture = S_AXIS_TVALID && S_AXIS_TREADY;
    // assign transfer_next_out = skid_ready;

    always_comb begin

        control_state_d = control_state_q;

        S_AXIS_TREADY = 1'b0; // only set in specific states
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
        exit_payload_d = exit_payload_q;
        skip_payload_d = skip_payload_q;
        if (control_state_q[IDLE_IDX]) begin
            S_AXIS_TREADY = 1'b1;
            if (S_AXIS_TVALID) begin
                packet_len_d = S_PAYLOAD_LEN;
                exit_payload_d = S_AXIS_TLAST;
                control_state_d = WRITE_HEADER;
                input_tvalid_d = '1; //mark input_tdata as valid non-transmitted data
                // We need to immediately propagate the output on the next cycle
                // output_data_d = {16'h63df, packet_id_q};
                // output_data_tvalid_d = 1'b1;
                // if (S_AXIS_TLAST) skip_payload_d = '1;

            end
        end else if (control_state_q[WRITE_HEADER_IDX]) begin
            S_AXIS_TREADY = 1'b0; //Hold off accepting more data while header is written
            output_data_tvalid_d = 1'b1; //This state will always have data ready?
            case (header_pos_q)
                1'b0: begin
                    // Is this going to produce a weird result? Or Okay with valid signaling?
                    output_data_d = {16'h63df, packet_id_q};
                    if (skid_ready) begin
                        header_pos_d = 1'b1;
                        // output_data_d = {packet_len_q, 16'h0};
                        // crc_update = 1'b1;
                    end
                end
                1'b1: begin
                    output_data_d = {packet_len_q, 16'h0};
                    if (skid_ready) begin
                        header_pos_d = 1'b0;
                        control_state_d = skip_payload_q ? WRITE_CRC : STREAM_PAYLOAD;
                        // S_AXIS_TREADY = !skip_payload_q;
                        // output_data_d = input_data_q;
                        // input_tvalid_d = valid_capture;
                        skip_payload_d = '0;
                        // if (S_AXIS_TLAST) exit_payload_d = '1;
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
            // If downstream can't accept data, we can't replace current data with new data => drop S_AXIS_TREADY.
            // Don't be ready once we are exiting payload, since next data will need to come into idle
            // TODO: We could potentially start next transistion here and skip IDLE, move directly to write_header
            S_AXIS_TREADY = (skid_ready || !input_tvalid_q) && !exit_payload_q;
            // Only update CRC on an accepted payload beat
            crc_update = skid_ready && input_tvalid_q;
            // Mark that the last payload beat was accepted by the slave
            if (S_AXIS_TVALID && S_AXIS_TREADY && S_AXIS_TLAST) begin
                exit_payload_d = 1'b1;
            end
            if (exit_payload_q && skid_ready && input_tvalid_q) begin
                S_AXIS_TREADY = '0;
                control_state_d = WRITE_CRC;
                exit_payload_d = 1'b0;

                //preload crc data here? or do we still need to wait for last tvalid
                // output_data_d = ~crc_value_q;
                // output_data_tvalid_d = 1'b1;
            end
        end else if (control_state_q[WRITE_CRC_IDX]) begin
            // Present canonical CRC-32 on the stream: apply final XOR (0xFFFFFFFF)
            crc_to_output = ~crc_value_q;
            
            output_data_d = crc_to_output;
            output_data_tvalid_d = 1'b1;
            // Only assert TLAST when the CRC beat will actually be transferred
            output_data_tlast_d = 1'b1;
            crc_hold = 1'b1;
            // In WRITE_CRC, data pipeline must necessarily be empty, so would be ready to accept new data?
            // No, because if skid_ready is low, could still fill up pipeline.
            S_AXIS_TREADY = 1'b0; // 1'b0 for now to not miss the IDLE exit transition, but should be made more robust
            if (skid_ready) begin //Final data transfer
                crc_hold = 1'b0;
                control_state_d = IDLE;
                // output_data_tlast_d = 1'b0;
                // output_data_tvalid_d = 1'b0; //Idle state next, no way to have valid output data yet currently
                crc_clear = 1'b1;
                packet_id_d = packet_id_q + 1'b1;
            end
        end
        s_axis_tvalid_seen_d = S_AXIS_TVALID && S_AXIS_TREADY; //should be S_AXIS_TVALID or s_axis_tvalid_seen_q?
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

    always_comb begin 
        skid_out_tdata_d = skid_out_tdata_q;
        skid_out_tvalid_d = skid_out_tvalid_q;
        skid_out_tlast_d = skid_out_tlast_q;
        if (M_AXIS_TREADY) begin
            if (skid_out_tvalid_q) begin
                next_io_tdata = skid_out_tdata_q;
                next_io_tvalid = 1'b1;
                next_io_tlast = skid_out_tlast_q;
                skid_out_tvalid_d = 1'b0;
            end else begin
                next_io_tdata = output_data_d;
                next_io_tvalid = output_data_tvalid_d;
                next_io_tlast = output_data_tlast_d;
            end
        end else begin
            next_io_tdata = out_tdata_q;
            next_io_tvalid = out_tvalid_q;
            next_io_tlast = out_tlast_q;
            if (!skid_out_tvalid_q) begin
                skid_out_tdata_d = output_data_d;
                skid_out_tvalid_d = output_data_tvalid_d;
                skid_out_tlast_d  = output_data_tlast_d;
            end
        end
    end


// Skid buffer instantiation
// axis_skid_buffer #(
//     .P_DATA_WIDTH(P_DATA_WIDTH)
// ) output_skid_buffer (
//     .CLK(CLK),
//     .RST_N(RST_N),

//     //Upstream Interface
//     .S_AXIS_TVALID(output_data_tvalid_d),
//     .S_AXIS_TREADY(skid_ready),
//     .S_AXIS_TDATA(output_data_d),
//     .S_AXIS_TLAST(output_data_tlast_d),

//     //Downstream
//     .M_AXIS_TVALID(skid_out_tvalid),
//     .M_AXIS_TREADY(M_AXIS_TREADY),
//     .M_AXIS_TDATA(skid_out_tdata),
//     .M_AXIS_TLAST(skid_out_tlast)
// );

genvar i;
generate
    for (i = 0; i < 32; i++) begin : gen_tdata_out
        ODDRE1 #(
            .SIM_DEVICE("ULTRASCALE_PLUS")
        ) tdata_forward_inst (
            .Q(M_AXIS_TDATA[i]),
            .C(CLK),
            .D1(next_io_tdata[i]), // Feed the same data bit to both DDR ports
            .D2(next_io_tdata[i]), // to keep the value stable across the whole cycle
            .SR(1'b0)
        );
    end
endgenerate

ODDRE1 #(
    .SIM_DEVICE("ULTRASCALE_PLUS")
) tlast_forward_inst (
    .Q(M_AXIS_TLAST), .C(CLK), .D1(next_io_tlast), .D2(next_io_tlast), .SR(1'b0)
);

ODDRE1 #(
    .SIM_DEVICE("ULTRASCALE_PLUS")
) tvalid_forward_inst (
    .Q(M_AXIS_TVALID), .C(CLK), .D1(next_io_tvalid), .D2(next_io_tvalid),
    .SR(1'b0)
);

    ODDRE1 #(
    .SIM_DEVICE("ULTRASCALE_PLUS")
) rx_clk_forward_inst (
    .Q  (M_AXIS_ACLK),  // Connects directly to your new top-level output port
    .C  (CLK),          // Driven by your standard INTERNAL 250 MHz system clock
    .D1 (1'b1),         // Tied High: Out-of-phase or edge-aligned options
    .D2 (1'b0),         // Tied Low
    .SR (1'b0)          // No reset required for continuous clocking
);

    assign M_AXIS_TKEEP = {KEEP_WIDTH{1'b1}};

endmodule
