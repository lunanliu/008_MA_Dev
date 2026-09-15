`timescale 1ns/1ps
// Random-read lease adapter for the T03 *bare* latency-2 RAM port.
// This is NOT compatible with t03_owned_uram_frame_bank's sequential frontier.
// The owner/arbitrator and any clock crossing remain outside this unit.
module t06_raw_reader_4lane #(
    parameter integer DEPTH_BEATS=335872,
    parameter integer ADDR_WIDTH=19,
    parameter integer OUTPUT_DEPTH=16
) (
    input logic clk, input logic rst,
    input logic context_valid,
    input logic [31:0] context_frame, context_generation,
    input logic signed [31:0] context_origin,
    input logic [31:0] context_sample_count,
    input logic s_valid, output logic s_ready,
    input logic [31:0] s_frame, s_tag,
    input logic signed [31:0] s_abs,
    input logic [3:0] s_symbol,
    input logic [8:0] s_beat,
    input logic [127:0] s_phase,
    input logic s_end,
    output logic bank_req_valid, input logic bank_req_ready,
    output logic [ADDR_WIDTH-1:0] bank_req_addr,
    output logic [31:0] bank_req_frame, bank_req_generation,
    input logic bank_rsp_valid,
    input logic [ADDR_WIDTH-1:0] bank_rsp_addr,
    input logic [31:0] bank_rsp_frame, bank_rsp_generation,
    input logic [127:0] bank_rsp_data,
    output logic m_valid, input logic m_ready,
    output logic [63:0] m_i,m_q,
    output logic [31:0] m_frame,m_generation,m_tag,
    output logic signed [31:0] m_abs,
    output logic [3:0] m_symbol,
    output logic [8:0] m_beat,
    output logic [127:0] m_phase,
    output logic m_end,
    output logic [$clog2(OUTPUT_DEPTH):0] pending_count,
    output logic range_error_sticky, context_error_sticky, protocol_error_sticky
);
    localparam integer META_WIDTH=270;
    localparam integer FIFO_WIDTH=META_WIDTH+128;
    typedef struct packed {
        logic [31:0] frame_id,generation;
        logic signed [31:0] abs_sample;
        logic [3:0] symbol_id;
        logic [8:0] beat_index;
        logic [127:0] phase_codes;
        logic transaction_end;
        logic [31:0] tag;
    } metadata_t;
    metadata_t input_meta,saved_meta,issue_meta,pipe_meta[0:1],output_meta;
    logic signed [32:0] relative_sample,last_absolute;
    logic [ADDR_WIDTH-1:0] first_addr,last_issued_addr,saved_second_addr;
    logic [1:0] offset,saved_offset,issue_offset,pipe_offset[0:1];
    logic bad_range,bad_context,bad_fields,context_changed,busy_context_fault;
    logic [128:0] context_code,active_context;
    logic active_context_valid,cache_issued_valid,need_base,second_pending;
    logic issue_emit,issue_join,bank_fire,input_fire,output_fire,healthy,has_credit;
    logic [1:0] pipe_valid,pipe_emit,pipe_join;
    logic [ADDR_WIDTH-1:0] pipe_addr[0:1];
    logic [127:0] previous_word,output_data;
    logic [255:0] merged_words;
    logic [FIFO_WIDTH-1:0] fifo_din,fifo_dout;
    logic fifo_full,fifo_empty,fifo_wr_busy,fifo_rd_busy,fifo_overflow,fifo_underflow,fifo_write;
    logic rsp_match;

    initial begin
        if(OUTPUT_DEPTH<16 || (OUTPUT_DEPTH&(OUTPUT_DEPTH-1))!=0 || (1<<ADDR_WIDTH)<DEPTH_BEATS)
            $fatal(1,"T06_RAW_READER_PARAMETERS");
        if($bits(metadata_t)!=META_WIDTH) $fatal(1,"T06_RAW_READER_METADATA_WIDTH");
    end
    always_comb begin
        context_code={context_valid,context_frame,context_generation,context_origin,context_sample_count};
        context_changed=active_context_valid && context_code!=active_context;
        busy_context_fault=context_changed && (pending_count!=0 || second_pending || (|pipe_valid));
        relative_sample=$signed({s_abs[31],s_abs})-$signed({context_origin[31],context_origin});
        last_absolute=$signed({s_abs[31],s_abs})+33'sd3;
        bad_range=relative_sample<0 || relative_sample+33'sd3>=$signed({1'b0,context_sample_count}) ||
            relative_sample+33'sd3>=33'(DEPTH_BEATS*4) || last_absolute>33'sd2147483647;
        bad_context=!context_valid || s_frame!=context_frame || context_sample_count==0 ||
            {1'b0,context_sample_count}>33'(DEPTH_BEATS*4);
        bad_fields=s_symbol<3 || s_symbol>10 || s_end!=(s_beat==511);
        first_addr=relative_sample[ADDR_WIDTH+1:2];offset=relative_sample[1:0];
        input_meta='{frame_id:s_frame,generation:context_generation,abs_sample:s_abs,symbol_id:s_symbol,
            beat_index:s_beat,phase_codes:s_phase,transaction_end:s_end,tag:s_tag};
        healthy=!rst && !range_error_sticky && !context_error_sticky && !protocol_error_sticky && !busy_context_fault;
        has_credit=!fifo_wr_busy && !fifo_rd_busy && pending_count<OUTPUT_DEPTH;
        need_base=offset!=0 && !(cache_issued_valid && !context_changed && first_addr==last_issued_addr);
        s_ready=healthy && has_credit && !second_pending &&
            ((bad_range || bad_context || bad_fields) || bank_req_ready);
        bank_req_valid=healthy && (second_pending ||
            (s_valid && has_credit && !bad_range && !bad_context && !bad_fields));
        bank_req_addr=second_pending?saved_second_addr:(first_addr+((offset!=0 && !need_base)?1'b1:1'b0));
        bank_req_frame=second_pending?saved_meta.frame_id:s_frame;
        bank_req_generation=second_pending?saved_meta.generation:context_generation;
        issue_meta=second_pending?saved_meta:input_meta;
        issue_offset=second_pending?saved_offset:offset;
        issue_emit=second_pending || !need_base;
        issue_join=issue_offset!=0;
        bank_fire=bank_req_valid && bank_req_ready;
        input_fire=s_valid && s_ready;
        rsp_match=bank_rsp_valid==pipe_valid[1] && (!bank_rsp_valid ||
            (bank_rsp_addr==pipe_addr[1] && bank_rsp_frame==pipe_meta[1].frame_id &&
             bank_rsp_generation==pipe_meta[1].generation));
        merged_words={bank_rsp_data,previous_word};
        fifo_din={pipe_meta[1],pipe_join[1]?(128'(merged_words>>(32*pipe_offset[1]))):bank_rsp_data};
        fifo_write=healthy && bank_rsp_valid && pipe_valid[1] && pipe_emit[1] && rsp_match;
        m_valid=healthy && !fifo_empty && !fifo_rd_busy;
        {output_meta,output_data}=fifo_dout;
        m_frame=output_meta.frame_id;m_generation=output_meta.generation;m_abs=output_meta.abs_sample;
        m_symbol=output_meta.symbol_id;m_beat=output_meta.beat_index;m_phase=output_meta.phase_codes;
        m_end=output_meta.transaction_end;m_tag=output_meta.tag;
        for(int lane=0;lane<4;lane++)begin
            m_i[16*lane+:16]=output_data[32*lane+:16];m_q[16*lane+:16]=output_data[32*lane+16+:16];
        end
        output_fire=m_valid && m_ready;
    end
    always_ff @(posedge clk) begin
        if(rst)begin
            pending_count<='0;range_error_sticky<=0;context_error_sticky<=0;protocol_error_sticky<=0;
            second_pending<=0;cache_issued_valid<=0;active_context_valid<=0;active_context<='0;
            last_issued_addr<='0;saved_second_addr<='0;saved_meta<='0;saved_offset<='0;
            pipe_valid<='0;pipe_emit<='0;pipe_join<='0;previous_word<='0;
            for(int p=0;p<2;p++)begin pipe_meta[p]<='0;pipe_addr[p]<='0;pipe_offset[p]<='0;end
        end else begin
            pipe_valid[0]<=bank_fire;pipe_valid[1]<=pipe_valid[0];
            pipe_emit[0]<=issue_emit;pipe_emit[1]<=pipe_emit[0];
            pipe_join[0]<=issue_join;pipe_join[1]<=pipe_join[0];
            pipe_meta[0]<=issue_meta;pipe_meta[1]<=pipe_meta[0];
            pipe_addr[0]<=bank_req_addr;pipe_addr[1]<=pipe_addr[0];
            pipe_offset[0]<=issue_offset;pipe_offset[1]<=pipe_offset[0];
            if(bank_rsp_valid && rsp_match)previous_word<=bank_rsp_data;
            if(busy_context_fault)context_error_sticky<=1;
            if(!rsp_match || fifo_overflow || fifo_underflow || (fifo_write && fifo_full) ||
                (output_fire && pending_count==0))protocol_error_sticky<=1;
            if(context_changed && pending_count==0 && !second_pending && !(|pipe_valid))cache_issued_valid<=0;
            if(input_fire)begin
                if(bad_range)range_error_sticky<=1;
                if(bad_context)context_error_sticky<=1;
                if(bad_fields)protocol_error_sticky<=1;
            end
            case({input_fire && !bad_range && !bad_context && !bad_fields,output_fire})
                2'b10:pending_count<=pending_count+1'b1;
                2'b01:pending_count<=pending_count-1'b1;
                default:pending_count<=pending_count;
            endcase
            if(bank_fire)begin
                active_context<=context_code;active_context_valid<=1;cache_issued_valid<=1;last_issued_addr<=bank_req_addr;
                if(second_pending)second_pending<=0;
                else if(need_base)begin
                    second_pending<=1;saved_second_addr<=first_addr+1'b1;saved_meta<=input_meta;saved_offset<=offset;
                end
            end
        end
    end
    xpm_fifo_sync #(
        .FIFO_MEMORY_TYPE("distributed"),.ECC_MODE("no_ecc"),.SIM_ASSERT_CHK(0),.FIFO_WRITE_DEPTH(OUTPUT_DEPTH),
        .WRITE_DATA_WIDTH(FIFO_WIDTH),.READ_DATA_WIDTH(FIFO_WIDTH),
        .WR_DATA_COUNT_WIDTH($clog2(OUTPUT_DEPTH)+1),.RD_DATA_COUNT_WIDTH($clog2(OUTPUT_DEPTH)+1),
        .PROG_FULL_THRESH(OUTPUT_DEPTH-8),.PROG_EMPTY_THRESH(8),.READ_MODE("fwft"),.FIFO_READ_LATENCY(0),
        .DOUT_RESET_VALUE("0"),.FULL_RESET_VALUE(0),.USE_ADV_FEATURES("0707"),.WAKEUP_TIME(0)
    ) u_output_fifo (
        .sleep(1'b0),.rst(rst),.wr_clk(clk),.wr_en(fifo_write),.din(fifo_din),.full(fifo_full),.prog_full(),
        .wr_data_count(),.overflow(fifo_overflow),.wr_rst_busy(fifo_wr_busy),.almost_full(),.wr_ack(),
        .rd_en(output_fire),.dout(fifo_dout),.empty(fifo_empty),.prog_empty(),.rd_data_count(),
        .underflow(fifo_underflow),.rd_rst_busy(fifo_rd_busy),.almost_empty(),.data_valid(),
        .injectsbiterr(1'b0),.injectdbiterr(1'b0),.sbiterr(),.dbiterr());
endmodule
