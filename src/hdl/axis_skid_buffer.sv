`timescale 1ns/1ps

module axis_skid_buffer #(
    parameter int P_DATA_WIDTH = 32
) (
    input  logic                CLK,
    input  logic                RST_N,

    // Upstream Interface
    input  logic                  S_AXIS_TVALID,
    output logic                  S_AXIS_TREADY,
    input  logic [P_DATA_WIDTH-1:0] S_AXIS_TDATA,
    input  logic                  S_AXIS_TLAST,

    // Downstream Interface
    output logic                  M_AXIS_TVALID,
    input  logic                  M_AXIS_TREADY,
    output logic [P_DATA_WIDTH-1:0] M_AXIS_TDATA,
    output logic                  M_AXIS_TLAST
);

    // Primary pipeline registers
    logic                  pipe_tvalid_q, pipe_tvalid_d;
    logic [P_DATA_WIDTH-1:0] pipe_tdata_q, pipe_tdata_d;
    logic                  pipe_tlast_q, pipe_tlast_d;

    // Shadow/skid overflow registers
    logic                  skid_tvalid_q, skid_tvalid_d;
    logic [P_DATA_WIDTH-1:0] skid_tdata_q, skid_tdata_d;
    logic                  skid_tlast_q, skid_tlast_d;

    assign S_AXIS_TREADY = !skid_tvalid_q;
    assign M_AXIS_TVALID = pipe_tvalid_q;
    assign M_AXIS_TDATA = pipe_tdata_q;
    assign M_AXIS_TLAST = pipe_tlast_q;

    always_ff @(posedge CLK) begin
        if (!RST_N) begin
            pipe_tvalid_q <= 1'b0;
            pipe_tdata_q  <= '0;
            pipe_tlast_q <= 1'b0;
            skid_tvalid_q <= 1'b0;
            skid_tdata_q <= '0;
            skid_tlast_q <= 1'b0;
        end else begin
            pipe_tvalid_q <= pipe_tvalid_d;
            pipe_tdata_q <= pipe_tdata_d;
            pipe_tlast_q <= pipe_tlast_d;
            skid_tvalid_q <= skid_tvalid_d;
            skid_tdata_q <= skid_tdata_d;
            skid_tlast_q <= skid_tlast_d;
        end
    end

    always_comb begin
        pipe_tvalid_d = pipe_tvalid_q;
        pipe_tdata_d = pipe_tdata_q;
        pipe_tlast_d = pipe_tlast_q;
        skid_tvalid_d = skid_tvalid_q;
        skid_tdata_d = skid_tdata_q;
        skid_tlast_d = skid_tlast_q;
        case ({S_AXIS_TREADY, M_AXIS_TREADY})
            2'b11: begin
                // No stalls, send data through
                pipe_tvalid_d = S_AXIS_TVALID;
                pipe_tdata_d = S_AXIS_TDATA;
                pipe_tlast_d = S_AXIS_TLAST;
            end

            2'b10: begin
                // Downstream device has stalled, catch data in skid buffers
                skid_tvalid_d = S_AXIS_TVALID;
                skid_tdata_d = S_AXIS_TDATA;
                skid_tlast_d = S_AXIS_TLAST;
            end

            2'b01: begin
                // Downstream reopened and there is valid data in the skid buffer, send out before showing ready upstream
                pipe_tvalid_d = skid_tvalid_q;
                pipe_tdata_d = skid_tdata_q;
                pipe_tlast_d = skid_tlast_q;
                skid_tvalid_d = 1'b0;
            end

            default: begin

            end
        endcase
    end


endmodule
