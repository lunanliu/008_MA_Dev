// Frozen five-sum SWLS contribution pipeline, exact official multipliers.
module t06_five_sum_accumulator (
    input logic clk,input logic rst,
    input logic start_valid,output logic start_ready,input logic [31:0] start_frame_id,
    input logic s_valid,output logic s_ready,
    input logic [1:0] s_pair,input logic signed [10:0] s_bin,
    input logic [17:0] s_weight,input logic signed [47:0] s_phase,input logic s_last,
    output logic m_valid,input logic m_ready,output logic [31:0] m_frame_id,
    output logic [29:0] m_s0,output logic signed [40:0] m_s1,output logic [47:0] m_s2,
    output logic signed [75:0] m_t0,output logic signed [84:0] m_t1,
    output logic m_error,output logic [2:0] m_error_code,
    output logic [12:0] accepted_count,output logic [12:0] accumulated_count
);
    localparam integer MULT_LATENCY=3,PIPE_LATENCY=6;
    logic busy,start_fire,accept,clear_ip,input_error;
    logic [1:0] expected_pair;
    logic [10:0] expected_bin_index;
    logic signed [10:0] expected_bin;
    logic [PIPE_LATENCY-1:0] valid_pipe;
    logic [17:0] weight_pipe[0:PIPE_LATENCY-1];
    logic signed [10:0] bin_pipe[0:MULT_LATENCY-1];
    logic signed [47:0] phase_pipe[0:MULT_LATENCY-1];
    logic signed [28:0] wk,wk_pipe[0:MULT_LATENCY-1];
    logic signed [65:0] wy,wy_pipe[0:MULT_LATENCY-1];
    logic signed [39:0] wkk;
    logic signed [76:0] wky;
    logic [30:0] sum0_next;
    logic signed [41:0] sum1_next;
    logic [48:0] sum2_next;
    logic signed [76:0] total0_next;
    logic signed [85:0] total1_next;
    logic sum_error;
    assign start_ready=!rst && !busy && !m_valid;
    assign start_fire=start_valid && start_ready;
    assign s_ready=!rst && busy && !m_valid && accepted_count<13'd6560;
    assign accept=s_valid && s_ready;
    assign clear_ip=rst || start_fire;
    assign expected_bin=(expected_bin_index<820) ? $signed(expected_bin_index+11'd1) :
        $signed({1'b0,expected_bin_index})-12'sd1640;
    assign input_error=s_pair!=expected_pair || s_bin!=expected_bin ||
        s_weight<18'd1 || s_weight>18'd131072 ||
        s_phase< -48'sd35184372088832 || s_phase>48'sd35184372088831 ||
        s_last!=(accepted_count==13'd6559);
    t06_fs_mult_u18_s11 u_wk(.CLK(clk),.SCLR(clear_ip),.A(s_weight),.B(s_bin),.P(wk));
    t06_fs_mult_u18_s48 u_wy(.CLK(clk),.SCLR(clear_ip),.A(s_weight),.B(s_phase),.P(wy));
    t06_fs_mult_s29_s11 u_wkk(.CLK(clk),.SCLR(clear_ip),.A(wk),.B(bin_pipe[2]),.P(wkk));
    t06_fs_mult_s29_s48 u_wky(.CLK(clk),.SCLR(clear_ip),.A(wk),.B(phase_pipe[2]),.P(wky));
    always_comb begin
        sum0_next={1'b0,m_s0}+{{13{1'b0}},weight_pipe[5]};
        sum1_next=$signed({m_s1[40],m_s1})+$signed({{13{wk_pipe[2][28]}},wk_pipe[2]});
        sum2_next={1'b0,m_s2}+{{9{1'b0}},wkk};
        total0_next=$signed({m_t0[75],m_t0})+$signed({{11{wy_pipe[2][65]}},wy_pipe[2]});
        total1_next=$signed({m_t1[84],m_t1})+$signed({{9{wky[76]}},wky});
        sum_error=sum0_next[30] || sum1_next[41]!=sum1_next[40] || sum2_next[48] ||
            wkk[39] || total0_next[76]!=total0_next[75] || total1_next[85]!=total1_next[84];
    end
    integer stage;
    always_ff @(posedge clk) begin
        if(rst || start_fire) begin
            busy<=start_fire;m_valid<=0;m_error<=0;m_error_code<=0;
            m_frame_id<=rst ? 32'b0 : start_frame_id;
            accepted_count<=0;accumulated_count<=0;expected_pair<=0;expected_bin_index<=0;
            valid_pipe<=0;m_s0<=0;m_s1<=0;m_s2<=0;m_t0<=0;m_t1<=0;
            for(stage=0;stage<PIPE_LATENCY;stage=stage+1)weight_pipe[stage]<=0;
            for(stage=0;stage<MULT_LATENCY;stage=stage+1) begin
                bin_pipe[stage]<=0;phase_pipe[stage]<=0;wk_pipe[stage]<=0;wy_pipe[stage]<=0;
            end
        end else begin
            valid_pipe<={valid_pipe[4:0],accept && !input_error};
            weight_pipe[0]<=s_weight;bin_pipe[0]<=s_bin;phase_pipe[0]<=s_phase;
            wk_pipe[0]<=wk;wy_pipe[0]<=wy;
            for(stage=1;stage<PIPE_LATENCY;stage=stage+1)weight_pipe[stage]<=weight_pipe[stage-1];
            for(stage=1;stage<MULT_LATENCY;stage=stage+1) begin
                bin_pipe[stage]<=bin_pipe[stage-1];phase_pipe[stage]<=phase_pipe[stage-1];
                wk_pipe[stage]<=wk_pipe[stage-1];wy_pipe[stage]<=wy_pipe[stage-1];
            end
            if(m_valid && m_ready)begin m_valid<=0;busy<=0;end
            if(accept)begin
                accepted_count<=accepted_count+13'd1;
                if(expected_bin_index==11'd1639)begin expected_bin_index<=0;expected_pair<=expected_pair+2'd1;end
                else expected_bin_index<=expected_bin_index+11'd1;
            end
            if(busy && !m_valid && valid_pipe[5])begin
                m_s0<=sum0_next[29:0];m_s1<=sum1_next[40:0];m_s2<=sum2_next[47:0];
                m_t0<=total0_next[75:0];m_t1<=total1_next[84:0];
                accumulated_count<=accumulated_count+13'd1;
                if(accumulated_count==13'd6559)begin m_valid<=1;m_error<=0;m_error_code<=0;end
            end
            if((accept && input_error) || (busy && !m_valid && valid_pipe[5] && sum_error))begin
                m_valid<=1;m_error<=1;m_error_code<=(accept && input_error) ? 3'd6 : 3'd4;
                valid_pipe<=0;m_s0<=0;m_s1<=0;m_s2<=0;m_t0<=0;m_t1<=0;
            end
        end
    end
`ifndef SYNTHESIS
    always @(posedge clk) if(!rst)begin
        if(accepted_count>6560 || accumulated_count>accepted_count)
            $fatal(1,"T06 five-sum observation accounting failed");
        if(m_valid && !m_error && (accepted_count!=6560 || accumulated_count!=6560))
            $fatal(1,"T06 five-sum premature result");
    end
`endif
endmodule
