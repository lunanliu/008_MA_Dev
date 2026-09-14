`timescale 1ns/1ps
// Concrete single-client qualification owner for the UNCHANGED T03 main FFT.
// This is not the future T14 multi-client scheduler. Exactly one XFFT is instantiated.
module t06_main_fft_exclusive_owner(
    input logic clk_125,clk_500,rst,
    input logic lease_valid,output logic lease_ready,input logic [31:0] lease_frame_id,
    input logic lease_release,abort_request,output logic abort_done,
    input logic s_valid,output logic s_ready,input logic [127:0] s_data,input logic s_last,
    output logic m_valid,input logic m_ready,output logic [127:0] m_data,output logic m_last,
    output logic error_sticky,output logic owned,output logic [31:0] active_frame_id,
    output logic [12:0] accepted_input_beats,accepted_output_beats,
    output logic [3:0] accepted_input_last,accepted_output_last
);
    typedef enum logic [1:0] {BOOT,IDLE,OWNED,ABORT_RESET} state_t;
    state_t state;
    logic [4:0] reset_count;
    logic core_rst_n,core_s_ready,core_m_valid;
    logic [127:0] core_m_data;
    logic core_m_last;
    logic in_overflow,in_underflow,out_overflow,out_underflow,fft_protocol,fft_overflow;
    logic [3:0] error500,error125;
    logic core_error,input_fire,output_fire;
    assign core_rst_n=!rst && state!=BOOT && state!=ABORT_RESET;
    assign error500={fft_overflow,fft_protocol,out_overflow,in_underflow};
    xpm_cdc_array_single #(.DEST_SYNC_FF(2),.INIT_SYNC_FF(0),.SIM_ASSERT_CHK(0),.SRC_INPUT_REG(0),.WIDTH(4))
        error_sync(.src_clk(clk_500),.src_in(error500),.dest_clk(clk_125),.dest_out(error125));
    assign core_error=(|error125) || in_overflow || out_underflow;
    assign owned=!rst && state==OWNED;
    assign lease_ready=!rst && state==IDLE && core_s_ready && !core_m_valid && !core_error && !error_sticky && !abort_request;
    assign s_ready=owned && !error_sticky && !core_error && !abort_request && accepted_input_beats<4096 && core_s_ready;
    assign input_fire=s_valid && s_ready;
    // A late error reports failure but does not withdraw an already offered beat.
    // Only the explicit abort/reset cancels it; its receiver must fail the lease.
    assign m_valid=owned && !abort_request && core_m_valid && accepted_output_beats<4096;
    assign output_fire=m_valid && m_ready;
    assign m_data=core_m_data;
    assign m_last=core_m_last;
    t03_main_fft_service fft(
        .clk_125(clk_125),.clk_500(clk_500),.rst_n(core_rst_n),
        .s_valid(s_valid && owned && !error_sticky && !core_error && !abort_request && accepted_input_beats<4096),
        .s_ready(core_s_ready),.s_data(s_data),.s_transaction_end(s_last),
        .m_valid(core_m_valid),.m_ready(m_ready && owned && !abort_request && accepted_output_beats<4096),
        .m_data(core_m_data),.m_transaction_end(core_m_last),
        .ingress_overflow(in_overflow),.ingress_underflow(in_underflow),.egress_overflow(out_overflow),
        .egress_underflow(out_underflow),.xfft_protocol_error(fft_protocol),.xfft_overflow(fft_overflow));
    always_ff @(posedge clk_125)begin
        if(rst)begin
            state<=BOOT;reset_count<=0;abort_done<=0;error_sticky<=0;active_frame_id<=0;
            accepted_input_beats<=0;accepted_output_beats<=0;accepted_input_last<=0;accepted_output_last<=0;
        end else begin
            abort_done<=0;
            case(state)
                BOOT,ABORT_RESET:begin
                    error_sticky<=0;
                    if(reset_count==15)begin
                        if(state==ABORT_RESET)abort_done<=1;
                        state<=IDLE;reset_count<=0;
                    end else reset_count<=reset_count+1'b1;
                end
                IDLE:begin
                    if(lease_valid && lease_ready)begin
                        state<=OWNED;active_frame_id<=lease_frame_id;
                        accepted_input_beats<=0;accepted_output_beats<=0;accepted_input_last<=0;accepted_output_last<=0;
                    end
                    if(core_m_valid || core_error || s_valid || lease_release)error_sticky<=1;
                end
                OWNED:begin
                    if(input_fire)begin
                        accepted_input_beats<=accepted_input_beats+1'b1;
                        if(s_last)accepted_input_last<=accepted_input_last+1'b1;
                        if(s_last!=(accepted_input_beats[8:0]==511))error_sticky<=1;
                    end
                    if(output_fire)begin
                        accepted_output_beats<=accepted_output_beats+1'b1;
                        if(core_m_last)accepted_output_last<=accepted_output_last+1'b1;
                        if(core_m_last!=(accepted_output_beats[8:0]==511))error_sticky<=1;
                    end
                    if(core_error || (core_m_valid && accepted_output_beats>=4096) ||
                        (s_valid && accepted_input_beats>=4096))error_sticky<=1;
                    if(lease_release)begin
                        if(accepted_input_beats==4096 && accepted_output_beats==4096 &&
                            accepted_input_last==8 && accepted_output_last==8 && !core_m_valid && !core_error && !error_sticky)
                            state<=IDLE;
                        else error_sticky<=1;
                    end
                    // Abort is the only normal way to clear a partial failed FFT job.
                    if(abort_request)begin state<=ABORT_RESET;reset_count<=0;end
                end
                default:begin state<=ABORT_RESET;reset_count<=0;error_sticky<=1;end
            endcase
        end
    end
endmodule
