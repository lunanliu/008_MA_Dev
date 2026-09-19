`timescale 1ns / 1ps

module sfo_uram_frame_bank #(
    // Keep packed literal inference for Vivado 2021.1 XPM numeric/string dispatch.
    parameter MEMORY_PRIMITIVE="ultra",
    parameter bit SEGMENTED = 1'b0,
    parameter int unsigned BEAT_WIDTH  = 128,
    parameter int unsigned DEPTH_BEATS = 335_872,
    parameter int unsigned ADDR_WIDTH  = 19
) (
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  wr_en,
    input  logic [ADDR_WIDTH-1:0] wr_addr,
    input  logic [BEAT_WIDTH-1:0] wr_data,
    input  logic                  rd_en,
    input  logic [ADDR_WIDTH-1:0] rd_addr,
    output logic [BEAT_WIDTH-1:0] rd_data,
    output wire                   rd_valid,
    output wire                   wr_commit,
    output wire [ADDR_WIDTH-1:0]  wr_commit_addr
);
  initial begin
    if ((1 << ADDR_WIDTH) < DEPTH_BEATS) $error("ADDR_WIDTH cannot address DEPTH_BEATS");
  end

  generate if(SEGMENTED)begin : segmented
    // e0 command capture; e1 memory access; e2 local read output;
    // e3/e4/e5 registered selection; the consumer samples at e6.
    localparam integer SEG_ADDR=(MEMORY_PRIMITIVE=="ultra")?14:12;
    localparam integer SEG_WORDS=(1<<SEG_ADDR);
    localparam integer SEG_COUNT=(DEPTH_BEATS+SEG_WORDS-1)/SEG_WORDS;
    localparam integer L1=(SEG_COUNT+3)/4,L2=(L1+3)/4;
    wire [BEAT_WIDTH-1:0] leaf_data[0:SEG_COUNT-1];
    wire [SEG_COUNT-1:0] leaf_valid;
    logic [BEAT_WIDTH-1:0] mux1[0:L1-1],mux2[0:L2-1],mux3;
    logic [L1-1:0] valid1;
    logic [L2-1:0] valid2;
    logic valid3,write_pending;
    logic [ADDR_WIDTH-1:0] commit_address;
    initial begin
      if((MEMORY_PRIMITIVE!="ultra" && MEMORY_PRIMITIVE!="block") || DEPTH_BEATS%4096!=0 ||
         ADDR_WIDTH<=SEG_ADDR || SEG_COUNT>64) $error("Unsupported segmented URAM geometry");
    end
    always_ff @(posedge clk)begin
      if(rst)write_pending<=0;
      else write_pending<=wr_en && wr_addr<DEPTH_BEATS;
      commit_address<=wr_addr;
    end
    assign wr_commit=write_pending && !rst;
    assign wr_commit_addr=commit_address;
    if(SEG_COUNT<=16)begin : two_select_levels
      assign rd_valid=valid2[0] && !rst;
      assign rd_data=mux2[0];
    end else begin : three_select_levels
      assign rd_valid=valid3 && !rst;
      assign rd_data=mux3;
    end
    for(genvar seg=0;seg<SEG_COUNT;seg=seg+1)begin : leaf
      localparam integer WORDS=((DEPTH_BEATS-seg*SEG_WORDS)<SEG_WORDS)?
          (DEPTH_BEATS-seg*SEG_WORDS):SEG_WORDS;
      localparam integer LAW=$clog2(WORDS);
      // These local boundaries intentionally survive synthesis. Data FFs have
      // no reset/CE; only local command bits authorize physical memory effects.
      (* dont_touch="true" *) logic [BEAT_WIDTH-1:0] write_data_q;
      (* dont_touch="true" *) logic [LAW-1:0] write_address_q,read_address_q;
      (* dont_touch="true" *) logic write_command_q,read_command_q;
      logic [1:0] read_valid_q;
      wire write_select=wr_addr[ADDR_WIDTH-1:SEG_ADDR]==seg && wr_addr<DEPTH_BEATS;
      wire read_select=rd_addr[ADDR_WIDTH-1:SEG_ADDR]==seg && rd_addr<DEPTH_BEATS;
      always_ff @(posedge clk)begin
        write_data_q<=wr_data;
        write_address_q<=wr_addr[LAW-1:0];read_address_q<=rd_addr[LAW-1:0];
        if(rst)begin write_command_q<=0;read_command_q<=0;read_valid_q<=0;end
        else begin
          write_command_q<=wr_en && write_select;
          read_command_q<=rd_en && read_select;
          read_valid_q<={read_valid_q[0],read_command_q};
        end
      end
      assign leaf_valid[seg]=read_valid_q[1];
      xpm_memory_sdpram #(
        .ADDR_WIDTH_A(LAW),.ADDR_WIDTH_B(LAW),.AUTO_SLEEP_TIME(0),
        .BYTE_WRITE_WIDTH_A(BEAT_WIDTH),.CASCADE_HEIGHT(4),
        .CLOCKING_MODE("common_clock"),.ECC_MODE("no_ecc"),
        .MEMORY_INIT_FILE("none"),.MEMORY_INIT_PARAM("0"),.MEMORY_OPTIMIZATION("true"),
        .MEMORY_PRIMITIVE(MEMORY_PRIMITIVE),.MEMORY_SIZE(BEAT_WIDTH*WORDS),.MESSAGE_CONTROL(0),
        .READ_DATA_WIDTH_B(BEAT_WIDTH),.READ_LATENCY_B(2),.READ_RESET_VALUE_B("0"),
        .RST_MODE_B("SYNC"),.SIM_ASSERT_CHK(1),.USE_EMBEDDED_CONSTRAINT(0),
        .USE_MEM_INIT(0),.WAKEUP_TIME("disable_sleep"),
        .WRITE_DATA_WIDTH_A(BEAT_WIDTH),.WRITE_MODE_B("read_first")
      ) memory (
        .dbiterrb(),.doutb(leaf_data[seg]),.sbiterrb(),
        .addra(write_address_q),.addrb(read_address_q),.clka(clk),.clkb(clk),
        .dina(write_data_q),.ena(write_command_q&&!rst),.enb(read_command_q&&!rst),
        .injectdbiterra(1'b0),.injectsbiterra(1'b0),.regceb(1'b1),
        // Payload reset is unnecessary: command/selection valid owns observability.
        .rstb(1'b0),.sleep(1'b0),.wea(write_command_q&&!rst)
      );
    end
    for(genvar group=0;group<L1;group=group+1)begin : select1
      logic [BEAT_WIDTH-1:0] value;
      logic present;
      always_comb begin
        value='0;present=0;
        for(integer k=0;k<4;k=k+1)begin
          if(group*4+k<SEG_COUNT)begin
            value=value | (leaf_data[group*4+k] & {BEAT_WIDTH{leaf_valid[group*4+k]}});
            present=present | leaf_valid[group*4+k];
          end
        end
      end
      always_ff @(posedge clk)begin mux1[group]<=value;if(rst)valid1[group]<=0;else valid1[group]<=present;end
    end
    for(genvar group=0;group<L2;group=group+1)begin : select2
      logic [BEAT_WIDTH-1:0] value;
      logic present;
      always_comb begin
        value='0;present=0;
        for(integer k=0;k<4;k=k+1)begin
          if(group*4+k<L1)begin
            value=value | (mux1[group*4+k] & {BEAT_WIDTH{valid1[group*4+k]}});
            present=present | valid1[group*4+k];
          end
        end
      end
      always_ff @(posedge clk)begin mux2[group]<=value;if(rst)valid2[group]<=0;else valid2[group]<=present;end
    end
    logic [BEAT_WIDTH-1:0] final_value;
    always_comb begin
      final_value='0;
      for(integer k=0;k<L2;k=k+1)final_value=final_value | (mux2[k]&{BEAT_WIDTH{valid2[k]}});
    end
    always_ff @(posedge clk)begin mux3<=final_value;if(rst)valid3<=0;else valid3<=|valid2;end
  end else begin : legacy
    logic [1:0] read_valid_q;
    always_ff @(posedge clk)begin
      if(rst)read_valid_q<=0;else read_valid_q<={read_valid_q[0],rd_en};
    end
    assign rd_valid=read_valid_q[1] && !rst;
    assign wr_commit=wr_en && !rst;
    assign wr_commit_addr=wr_addr;
  xpm_memory_sdpram #(
      .ADDR_WIDTH_A(ADDR_WIDTH),
      .ADDR_WIDTH_B(ADDR_WIDTH),
      .AUTO_SLEEP_TIME(0),
      .BYTE_WRITE_WIDTH_A(BEAT_WIDTH),
      .CASCADE_HEIGHT(0),
      .CLOCKING_MODE("common_clock"),
      .ECC_MODE("no_ecc"),
      .MEMORY_INIT_FILE("none"),
      .MEMORY_INIT_PARAM("0"),
      .MEMORY_OPTIMIZATION("true"),
      .MEMORY_PRIMITIVE(MEMORY_PRIMITIVE),
      .MEMORY_SIZE(BEAT_WIDTH * DEPTH_BEATS),
      .MESSAGE_CONTROL(0),
      .READ_DATA_WIDTH_B(BEAT_WIDTH),
      .READ_LATENCY_B(2),
      .READ_RESET_VALUE_B("0"),
      .RST_MODE_B("SYNC"),
      .SIM_ASSERT_CHK(1),
      .USE_EMBEDDED_CONSTRAINT(0),
      .USE_MEM_INIT(0),
      .WAKEUP_TIME("disable_sleep"),
      .WRITE_DATA_WIDTH_A(BEAT_WIDTH),
      .WRITE_MODE_B("read_first")
  ) u_frame_memory (
      .dbiterrb      (),
      .doutb         (rd_data),
      .sbiterrb      (),
      .addra         (wr_addr),
      .addrb         (rd_addr),
      .clka          (clk),
      .clkb          (clk),
      .dina          (wr_data),
      .ena           (wr_en),
      .enb           (rd_en),
      .injectdbiterra(1'b0),
      .injectsbiterra(1'b0),
      .regceb        (1'b1),
      .rstb          (rst),
      .sleep         (1'b0),
      .wea           (wr_en)
  );
  end endgenerate
endmodule
