`timescale 1ns/1ps
module sync_frontend_tb;
    logic clk=0, reset_n=0;
    logic session_start=0,session_abort=0,stream_gap=0;
    logic s_valid=0,s_ready;
    logic [127:0] s_data=0;
    logic m_valid,m_ready=0;
    logic [287:0] m_result;
    logic [63:0] accepted_samples;
    logic [31:0] epoch,candidate_count,rejected_count,capture_drop_count,duplicate_count,confirmed_count;
    logic [1:0] snapshot_occupancy,snapshot_peak;
    logic [15:0] max_history_age,error_sticky;
    logic [127:0] words[0:32767];
    logic check_finish=0,checker_enable=1;
    string stream_file,rom_file;
    int beats,cycles=0,stall_count=0;
    always #4 clk=~clk;
    // ROM is an explicit project memory source, not a truth signal.
    sync_frontend_top dut(.*);
    sync_passive_checker checker_inst(
        .clk(clk),.rst_n(dut.core_rst_n && checker_enable),
        .sample_fire(s_valid&&s_ready),.sample_data(s_data),
        .metric_valid(dut.metric_valid),.metric_qualified(dut.metric_qualified),
        .metric_position(dut.metric_position),.metric_p_re(dut.metric_p_re),
        .metric_p_im(dut.metric_p_im),.metric_energy(dut.metric_energy),
        .m_valid(m_valid),.m_ready(m_ready),.m_result(m_result),.check_finish(check_finish)
    );
    always @(negedge clk) begin
        cycles++;
        if(m_valid && stall_count<128) begin m_ready=0;stall_count++;end
        else if(m_valid) m_ready=1;
        else begin m_ready=0;stall_count=0;end
        if(cycles>900000) $fatal(1,"TB cycle timeout accepted=%0d confirmed=%0d",accepted_samples,confirmed_count);
    end
    initial begin
        if(!$value$plusargs("STREAM_MEM=%s",stream_file) || !$value$plusargs("STREAM_BEATS=%d",beats)) $fatal(1,"Missing transport file/length");
        if(beats<1 || beats>32768) $fatal(1,"Input size");
        $readmemh(stream_file,words,0,beats-1);
        for(int k=0;k<beats;k++) if($isunknown(words[k])) $fatal(1,"Input load X at %0d",k);
        repeat(8) @(negedge clk);reset_n=1;
        while(!s_ready) @(negedge clk);
        // Driver depends only on transport sequence and fixed block boundaries.
        // Truth file is absent from this module and never controls this loop.
        for(int k=0;k<beats;k++) begin
            s_data=words[k];s_valid=1;
            @(posedge clk);
            while(!s_ready) @(posedge clk);
            @(negedge clk);
            if((k%256)==255) begin s_valid=0;repeat(8000) @(negedge clk);end
        end
        s_valid=0;s_data=0;
        repeat(150000) @(negedge clk);
        if(accepted_samples!=beats*4 || confirmed_count!=4 || snapshot_occupancy!=0 || error_sticky!=0)
            $fatal(1,"Frontend completion accepted=%0d frames=%0d occupied=%0d errors=%h rejected=%0d drops=%0d",accepted_samples,confirmed_count,snapshot_occupancy,error_sticky,rejected_count,capture_drop_count);
        if(rejected_count==0) $fatal(1,"No false candidate exercised");
        check_finish=1;@(negedge clk);check_finish=0;checker_enable=0;
        $display("SF002_FRONTEND_MAIN_PASS candidates=%0d rejected=%0d drops=%0d dedup=%0d snapshot_peak=%0d max_history_age=%0d",candidate_count,rejected_count,capture_drop_count,duplicate_count,snapshot_peak,max_history_age);
        // True discontinuity resets detector history and coordinates in a new epoch.
        // Begin another raw capture and interrupt it before any accepted result.
        for(int k=1024;k<2048;k++) begin
            s_data=words[k];s_valid=1;
            @(posedge clk);while(!s_ready) @(posedge clk);@(negedge clk);
        end
        s_valid=0;
        stream_gap=1;@(negedge clk);stream_gap=0;
        repeat(32) @(negedge clk);
        if(epoch!=1 || accepted_samples!=0 || m_valid || snapshot_occupancy!=0) $fatal(1,"Gap flush failed");
        session_abort=1;@(negedge clk);session_abort=0;
        repeat(32) @(negedge clk);
        if(s_ready || epoch!=2) $fatal(1,"Abort did not disarm");
        session_start=1;@(negedge clk);session_start=0;
        repeat(32) @(negedge clk);
        if(!s_ready || epoch!=3) $fatal(1,"Session restart failed");
        reset_n=0;repeat(8) @(negedge clk);reset_n=1;
        repeat(32) @(negedge clk);
        if(epoch!=0 || accepted_samples!=0 || m_valid) $fatal(1,"Reset failed");
        $display("SF002_SESSION_CONTROL_PASS gap_epoch=1 abort_epoch=2 restart_epoch=3 reset_epoch=0");
        $display("SF002_AUTONOMOUS_SHORT_PASS");$finish;
    end
endmodule
