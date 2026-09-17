`timescale 1ns/1ps
// Passive only: this module has no output connected to the DUT or source.
module sync_passive_checker (
    input logic clk, rst_n,
    input logic sample_fire,
    input logic [127:0] sample_data,
    input logic metric_valid, metric_qualified,
    input logic [63:0] metric_position,
    input logic signed [42:0] metric_p_re, metric_p_im,
    input logic [41:0] metric_energy,
    input logic m_valid, m_ready,
    input logic [287:0] m_result,
    input logic check_finish
);
    logic [31:0] accepted [0:131071];
    logic [127:0] truth [0:3];
    longint unsigned accepted_count, metrics, results;
    longint signed sum_re, sum_im, sum_energy;
    logic [287:0] held_result;
    logic held;
    integer trace_file;
    string truth_file;
    function automatic longint signed component(input logic [31:0] z, input bit q);
        if(q) component=$signed(z[31:16]); else component=$signed(z[15:0]);
    endfunction
    task automatic accumulate(input int n,input int signum);
        longint signed ai,aq,bi,bq;
        ai=component(accepted[n],0);aq=component(accepted[n],1);
        bi=component(accepted[n+1024],0);bq=component(accepted[n+1024],1);
        sum_re+=signum*(ai*bi+aq*bq);
        sum_im+=signum*(ai*bq-aq*bi);
        sum_energy+=signum*(bi*bi+bq*bq);
    endtask
    initial begin
        if(!$value$plusargs("TRUTH_MEM=%s",truth_file)) $fatal(1,"Missing passive truth path");
        $readmemh(truth_file,truth);
        for(int k=0;k<4;k++) if($isunknown(truth[k])) $fatal(1,"Truth load X at %0d",k);
        trace_file=$fopen("autonomous_results.csv","w");
        if(!trace_file) $fatal(1,"Cannot write result trace");
        $fdisplay(trace_file,"epoch,rx_frame_id,candidate_id,coarse_absolute,fine_absolute,cfo_hz,quality,status");
    end
    always @(posedge clk) begin
        logic signed [127:0] lhs,rhs;
        longint signed wanted_cfo,actual_cfo;
        if(!rst_n) begin
            accepted_count=0;metrics=0;results=0;sum_re=0;sum_im=0;sum_energy=0;held=0;
        end else begin
            if(sample_fire) begin
                if(accepted_count+4>131072) $fatal(1,"Checker capacity");
                for(int j=0;j<4;j++) accepted[accepted_count+j]=sample_data[j*32+:32];
                accepted_count+=4;
            end
            if(metric_valid) begin
                if(metric_position != metrics*4 || metric_position+2048>accepted_count) $fatal(1,"Metric coordinate %0d count %0d accepted %0d",metric_position,metrics,accepted_count);
                if(metrics==0) for(int n=0;n<1024;n++) accumulate(n,1);
                else for(int j=0;j<4;j++) begin
                    accumulate(int'(metric_position)-4+j,-1);
                    accumulate(int'(metric_position)+1020+j,1);
                end
                if($isunknown({metric_p_re,metric_p_im,metric_energy}) || $signed(metric_p_re)!=sum_re || $signed(metric_p_im)!=sum_im || metric_energy!=sum_energy)
                    $fatal(1,"Metric mismatch d=%0d actual=%0d,%0d,%0d expected=%0d,%0d,%0d",metric_position,metric_p_re,metric_p_im,metric_energy,sum_re,sum_im,sum_energy);
                lhs=128'(sum_re)*128'(sum_re)+128'(sum_im)*128'(sum_im);lhs=lhs*100;
                rhs=128'(sum_energy)*128'(sum_energy)*3;
                if(metric_qualified != (sum_energy>0 && lhs>=rhs)) $fatal(1,"Threshold mismatch d=%0d",metric_position);
                metrics++;
            end
            if(held && (!m_valid || m_result!==held_result)) $fatal(1,"Result changed while backpressured");
            held=m_valid&&!m_ready;
            if(held) held_result=m_result;
            if(m_valid&&m_ready) begin
                if(results>=4) $fatal(1,"False or repeated accepted frame");
                wanted_cfo=$signed(truth[results][31:0]);actual_cfo=$signed(m_result[63:32]);
                if(m_result[287:256]!=0 || m_result[255:224]!=results || m_result[127:64]!=truth[results][95:32] || !m_result[11])
                    $fatal(1,"Frame mismatch result=%0d epoch=%0d id=%0d fine=%0d expected=%0d status=%h",results,m_result[287:256],m_result[255:224],m_result[127:64],truth[results][95:32],m_result[15:0]);
                if(actual_cfo-wanted_cfo>1000 || actual_cfo-wanted_cfo < -1000) $fatal(1,"CFO error frame=%0d actual=%0d expected=%0d",results,actual_cfo,wanted_cfo);
                $fdisplay(trace_file,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h",m_result[287:256],m_result[255:224],m_result[223:192],m_result[191:128],m_result[127:64],actual_cfo,m_result[31:16],m_result[15:0]);
                results++;
            end
            if(check_finish) begin
                if(results!=4 || metrics!=(accepted_count-2048)/4+1) $fatal(1,"Completion mismatch frames=%0d metrics=%0d accepted=%0d",results,metrics,accepted_count);
                $display("SF002_PASSIVE_CHECK_PASS frames=4 accepted_samples=%0d metrics=%0d false_outputs=0 duplicate_outputs=0 fine_sample_errors=0",accepted_count,metrics);
                $fclose(trace_file);
            end
        end
    end
endmodule
