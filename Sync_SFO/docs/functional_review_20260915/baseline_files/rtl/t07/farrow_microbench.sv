`timescale 1ns/1ps
// Research arithmetic only. All non-power-of-two products use official Mult_Gen.
module farrow_add #(parameter integer W=18)(
 input wire clk,reset,add,input wire signed [W-1:0] a,b,
 output wire signed [W-1:0] s
);
 generate
 if(W==18)begin:g18 farrow_add_18 u_add(.CLK(clk),.SCLR(reset),.ADD(add),.A(a),.B(b),.S(s));end
 else if(W==20)begin:g20 farrow_add_20 u_add(.CLK(clk),.SCLR(reset),.ADD(add),.A(a),.B(b),.S(s));end
 else if(W==28)begin:g28 farrow_add_28 u_add(.CLK(clk),.SCLR(reset),.ADD(add),.A(a),.B(b),.S(s));end
 else if(W==34)begin:g34 farrow_add_34 u_add(.CLK(clk),.SCLR(reset),.ADD(add),.A(a),.B(b),.S(s));end
 else if(W==32)begin:g32 farrow_add_32 u_add(.CLK(clk),.SCLR(reset),.ADD(add),.A(a),.B(b),.S(s));end
 else if(W==36)begin:g36 farrow_add_36 u_add(.CLK(clk),.SCLR(reset),.ADD(add),.A(a),.B(b),.S(s));end
 else begin:bad initial $fatal(1,"Unsupported official C_AddSub width");end
 endgenerate
endmodule
module farrow_horner #(
  parameter integer D=16, M=8, G=D+3, P=G+M
)(
  input wire clk, input wire reset,
  input wire signed [G-1:0] a, branch,
  input wire [M-1:0] mu,
  output reg signed [G-1:0] y,
  output wire signed [P-1:0] product,
  output wire signed [P:0] full_sum,
  output reg saturated
);
  reg signed [G-1:0] bp[0:2];
  wire signed [63:0] p64={{(64-P){product[P-1]}},product};
  wire signed [63:0] b64={{(64-G){bp[2][G-1]}},bp[2]};
  wire signed [63:0] bshift64=b64<<<M;
  farrow_add #(.W(P+1)) h_add(.clk(clk),.reset(reset),.add(1'b1),.a({product[P-1],product}),.b(bshift64[P:0]),.s(full_sum));
  wire signed [63:0] held_sum64={{(63-P){full_sum[P]}},full_sum};
  wire signed [63:0] floor_value=held_sum64>>>M;
  wire [M-1:0] remainder_bits=full_sum[M-1:0];
  wire increment=(remainder_bits > (64'd1<<(M-1))) ||
                 ((remainder_bits == (64'd1<<(M-1))) && floor_value[0]);
  wire signed [63:0] rounded=floor_value+$signed({63'd0,increment});
  localparam signed [63:0] LIMIT_HI=(64'sd1<<(G-1))-1;
  localparam signed [63:0] LIMIT_LO=-(64'sd1<<(G-1));
  generate
    if(D==16 && M==8) begin: gen_lo
      farrow_mul_h16 u_mult(.CLK(clk),.SCLR(reset),.A(a),.B(mu),.P(product));
    end else if(D==18 && M==12) begin: gen_mid
      farrow_mul_h18 u_mult(.CLK(clk),.SCLR(reset),.A(a),.B(mu),.P(product));
    end else begin: gen_bad
      initial $fatal(1,"Unsupported Farrow Horner profile");
    end
  endgenerate
  integer i;
  always @(posedge clk) begin
    bp[0]<=branch;for(i=1;i<3;i=i+1) bp[i]<=bp[i-1];

    saturated<=(rounded>LIMIT_HI)||(rounded<LIMIT_LO);
    if(rounded>LIMIT_HI)y<=LIMIT_HI[G-1:0];
    else if(rounded<LIMIT_LO)y<=LIMIT_LO[G-1:0];
    else y<=rounded[G-1:0];
  end
  // Full-product and typed P+1 sum: no discarded arithmetic carry.
  // synthesis translate_off
  wire signed [63:0] sum64=p64+(b64<<<M);
  always @(posedge clk) if(!reset && !$isunknown(sum64)) begin
    if($signed({{(63-P){sum64[P]}},sum64[P:0]}) !== sum64)
      $fatal(1,"Horner typed full-sum overflow");
  end
  // synthesis translate_on
endmodule

module farrow_real #(
  parameter integer C=14, D=16, M=8,
  parameter integer G=D+3, W=D+C+2, T=D+C-3, P=G+M
)(
  input wire clk, input wire reset,
  input wire signed [D-1:0] xa,xb,xc,xd,
  input wire [M-1:0] mu,
  output wire [18*64-1:0] trace,
  output wire [17:0] saturation,
  output reg signed [D-1:0] y
);
  localparam integer BVAL=(C==14)?683:2731;
  wire signed [D+1:0] da_full,bc_full,ca_full,ab2_full;
  wire signed [D:0] da=da_full[D:0],bc=bc_full[D:0],ca=ca_full[D:0];
  wire signed [D+1:0] second_difference;
  reg signed [D+1:0] xc_first;
  reg signed [D-1:0] xbp;
  reg signed [D:0] bc_delay[0:2],ca_delay[0:2];
  reg signed [D+1:0] sec_delay[0:1];
  reg signed [D-1:0] b_delay[0:2];
  wire signed [T-1:0] t_product;
  wire signed [63:0] t64={{(64-T){t_product[T-1]}},t_product};
  wire signed [63:0] bc64={{(63-D){bc_delay[2][D]}},bc_delay[2]};
  wire signed [63:0] ca64={{(63-D){ca_delay[2][D]}},ca_delay[2]};
  wire signed [63:0] sec64={{(62-D){sec_delay[1][D+1]}},sec_delay[1]};
  wire signed [63:0] b64={{(64-D){b_delay[2][D-1]}},b_delay[2]};
  wire signed [63:0] bcshift64=bc64<<<(C-3);
  wire signed [63:0] raw2_wide=sec64<<<(C-3);
  wire signed [63:0] raw0_wide=b64<<<(C-2);
  wire signed [W-1:0] r3_first,raw1_ip;
  reg signed [W-1:0] r2_first,r0_first,ca_first;
  wire signed [W-1:0] raw[0:3];
  reg signed [W-1:0] raw0_hold,raw2_hold,raw3_hold;
  assign raw[0]=raw0_hold;assign raw[1]=raw1_ip;assign raw[2]=raw2_hold;assign raw[3]=raw3_hold;
  reg signed [G-1:0] branch[0:3];
  reg [3:0] branch_sat;
  wire signed [63:0] r3_ext={{(64-W){r3_first[W-1]}},r3_first};
  wire signed [63:0] ca_ext={{(64-W){ca_first[W-1]}},ca_first};

  reg [M-1:0] mu_delay[0:16];
  reg signed [G-1:0] b1_delay[0:4],b0_delay[0:9];
  wire signed [G-1:0] h2,h1,h0;
  wire signed [P-1:0] p2,p1,p0;
  wire signed [P:0] s2,s1,s0;
  wire sat2,sat1,sat0;
  reg final_sat;
  localparam signed [63:0] OUTPUT_HI=(64'sd1<<(D-1))-1;
  localparam signed [63:0] OUTPUT_LO=-(64'sd1<<(D-1));
  wire signed [63:0] h0_64={{(64-G){h0[G-1]}},h0};

  function automatic signed [63:0] rne_branch(input reg signed [W-1:0] value);
    reg signed [63:0] ex,fl;
    reg [C-3:0] rembits;
    reg inc;
    begin
      ex={{(64-W){value[W-1]}},value};fl=ex>>>(C-2);
      rembits=value[C-3:0];
      inc=(rembits>(64'd1<<(C-3))) || ((rembits==(64'd1<<(C-3))) && fl[0]);
      rne_branch=fl+$signed({63'd0,inc});
    end
  endfunction
  function automatic signed [G-1:0] saturate_branch(input reg signed [63:0] value);
    reg signed [63:0] hi,lo;
    begin
      hi=(64'sd1<<(G-1))-1;lo=-(64'sd1<<(G-1));
      if(value>hi)saturate_branch=hi[G-1:0];
      else if(value<lo)saturate_branch=lo[G-1:0];
      else saturate_branch=value[G-1:0];
    end
  endfunction
  generate
    if(C==14 && D==16 && M==8) begin: gen_lo
      farrow_mul_t16 u_mult(.CLK(clk),.SCLR(reset),.A(da),.B(10'd683),.P(t_product));
    end else if(C==16 && D==18 && M==12) begin: gen_mid
      farrow_mul_t18 u_mult(.CLK(clk),.SCLR(reset),.A(da),.B(12'd2731),.P(t_product));
    end else begin: gen_bad
      initial $fatal(1,"Unsupported Farrow real profile");
    end
  endgenerate
  integer i;
  reg signed [63:0] rounded_branch;
  always @(posedge clk) begin
    xbp<=xb;xc_first<={{2{xc[D-1]}},xc};
    bc_delay[0]<=bc;ca_delay[0]<=ca;sec_delay[0]<=second_difference;sec_delay[1]<=sec_delay[0];b_delay[0]<=xbp;
    for(i=1;i<3;i=i+1)begin bc_delay[i]<=bc_delay[i-1];ca_delay[i]<=ca_delay[i-1];
      b_delay[i]<=b_delay[i-1];end
    r2_first<=raw2_wide[W-1:0];r0_first<=raw0_wide[W-1:0];
    ca_first<=ca64<<<(C-3);
    raw0_hold<=r0_first;raw2_hold<=r2_first;raw3_hold<=r3_first;
    for(i=0;i<4;i=i+1)begin
      rounded_branch=rne_branch(raw[i]);branch[i]<=saturate_branch(rounded_branch);
      branch_sat[i]<=(rounded_branch>((64'sd1<<(G-1))-1)) || (rounded_branch<-(64'sd1<<(G-1)));
    end
    mu_delay[0]<=mu;for(i=1;i<17;i=i+1)mu_delay[i]<=mu_delay[i-1];
    b1_delay[0]<=branch[1];for(i=1;i<5;i=i+1)b1_delay[i]<=b1_delay[i-1];
    b0_delay[0]<=branch[0];for(i=1;i<10;i=i+1)b0_delay[i]<=b0_delay[i-1];
    final_sat<=(h0_64>OUTPUT_HI)||(h0_64<OUTPUT_LO);
    if(h0_64>OUTPUT_HI)y<=OUTPUT_HI[D-1:0];
    else if(h0_64<OUTPUT_LO)y<=OUTPUT_LO[D-1:0];else y<=h0[D-1:0];
  end
  wire signed [D+1:0] xa_pre={{2{xa[D-1]}},xa};
  wire signed [D+1:0] xb_pre={{2{xb[D-1]}},xb};
  wire signed [D+1:0] xc_pre={{2{xc[D-1]}},xc};
  wire signed [D+1:0] xd_pre={{2{xd[D-1]}},xd};
  wire signed [D+1:0] xb_twice=xb_pre<<<1;
  farrow_add #(.W(D+2)) pre_da(.clk(clk),.reset(reset),.add(1'b0),.a(xd_pre),.b(xa_pre),.s(da_full));
  farrow_add #(.W(D+2)) pre_bc(.clk(clk),.reset(reset),.add(1'b0),.a(xb_pre),.b(xc_pre),.s(bc_full));
  farrow_add #(.W(D+2)) pre_ca(.clk(clk),.reset(reset),.add(1'b0),.a(xc_pre),.b(xa_pre),.s(ca_full));
  farrow_add #(.W(D+2)) pre_ab2(.clk(clk),.reset(reset),.add(1'b0),.a(xa_pre),.b(xb_twice),.s(ab2_full));
  farrow_add #(.W(D+2)) pre_second(.clk(clk),.reset(reset),.add(1'b1),.a(ab2_full),.b(xc_first),.s(second_difference));
  farrow_add #(.W(W)) raw3_add(.clk(clk),.reset(reset),.add(1'b1),.a(t64[W-1:0]),.b(bcshift64[W-1:0]),.s(r3_first));
  farrow_add #(.W(W)) raw1_sub(.clk(clk),.reset(reset),.add(1'b0),.a(ca_first),.b(r3_first),.s(raw1_ip));
  farrow_horner #(.D(D),.M(M)) hstage2(.clk(clk),.reset(reset),.a(branch[3]),.branch(branch[2]),
    .mu(mu_delay[6]),.y(h2),.product(p2),.full_sum(s2),.saturated(sat2));
  farrow_horner #(.D(D),.M(M)) hstage1(.clk(clk),.reset(reset),.a(h2),.branch(b1_delay[4]),
    .mu(mu_delay[11]),.y(h1),.product(p1),.full_sum(s1),.saturated(sat1));
  farrow_horner #(.D(D),.M(M)) hstage0(.clk(clk),.reset(reset),.a(h1),.branch(b0_delay[9]),
    .mu(mu_delay[16]),.y(h0),.product(p0),.full_sum(s0),.saturated(sat0));
  genvar j;
  generate for(j=0;j<4;j=j+1)begin: trace_branch
    assign trace[j*64+:64]={{(64-W){raw[j][W-1]}},raw[j]};
    assign trace[(j+4)*64+:64]={{(64-G){branch[j][G-1]}},branch[j]};
  end endgenerate
  assign trace[8*64+:64]={{(64-P){p2[P-1]}},p2};
  assign trace[9*64+:64]={{(63-P){s2[P]}},s2};
  assign trace[10*64+:64]={{(64-G){h2[G-1]}},h2};
  assign trace[11*64+:64]={{(64-P){p1[P-1]}},p1};
  assign trace[12*64+:64]={{(63-P){s1[P]}},s1};
  assign trace[13*64+:64]={{(64-G){h1[G-1]}},h1};
  assign trace[14*64+:64]={{(64-P){p0[P-1]}},p0};
  assign trace[15*64+:64]={{(63-P){s0[P]}},s0};
  assign trace[16*64+:64]={{(64-G){h0[G-1]}},h0};
  assign trace[17*64+:64]={{(64-D){y[D-1]}},y};
  assign saturation={final_sat,sat0,2'b00,sat1,2'b00,sat2,2'b00,branch_sat,4'b0000};
  // synthesis translate_off
  wire signed [63:0] raw3_wide=t64+(bc64<<<(C-3));
  wire signed [63:0] raw1_wide=ca_ext-r3_ext;
  always @(posedge clk) if(!reset) begin
    if(!$isunknown(raw3_wide) && $signed({{(64-W){raw3_wide[W-1]}},raw3_wide[W-1:0]})!==raw3_wide)
      $fatal(1,"raw3 typed overflow");
    if(!$isunknown(raw2_wide) && $signed({{(64-W){raw2_wide[W-1]}},raw2_wide[W-1:0]})!==raw2_wide)
      $fatal(1,"raw2 typed overflow");
    if(!$isunknown(raw1_wide) && $signed({{(64-W){raw1_wide[W-1]}},raw1_wide[W-1:0]})!==raw1_wide)
      $fatal(1,"raw1 typed overflow");
  end
  // synthesis translate_on
endmodule

module farrow_microbench #(
  parameter integer C=14,D=16,M=8,LANES=16,REALS=2*LANES,
  parameter integer INPUT_BITS=REALS*4*D+LANES*M
)(
  input wire clk,reset,input_valid,
  input wire [31:0] input_tag,
  input wire [INPUT_BITS-1:0] input_data,
  output wire input_ready,
  output wire output_valid,
  output wire [31:0] output_tag,
  output wire [REALS*D-1:0] output_data,
  output wire [REALS*18*64-1:0] trace_data,
  output wire [REALS*18-1:0] saturation,
  output wire [17:0] trace_valid,
  output wire [18*32-1:0] trace_tag
);
  reg [22:0] valid_pipe;
  reg [31:0] tag_pipe[0:22];
  assign input_ready=!reset;
  assign output_valid=valid_pipe[22];assign output_tag=tag_pipe[22];
  integer i;
  always @(posedge clk)begin
    if(reset)begin valid_pipe<=0;for(i=0;i<23;i=i+1)tag_pipe[i]<=0;end
    else begin valid_pipe<={valid_pipe[21:0],input_valid};tag_pipe[0]<=input_tag;
      for(i=1;i<23;i=i+1)tag_pipe[i]<=tag_pipe[i-1];end
  end
  function automatic integer node_stage(input integer n);
    begin
      if(n<4)node_stage=5;else if(n<8)node_stage=6;
      else case(n)8:node_stage=9;9:node_stage=10;10:node_stage=11;
        11:node_stage=14;12:node_stage=15;13:node_stage=16;
        14:node_stage=19;15:node_stage=20;16:node_stage=21;default:node_stage=22;endcase
    end
  endfunction
  genvar r,n;
  generate
    for(r=0;r<REALS;r=r+1)begin: real_channel
      farrow_real #(.C(C),.D(D),.M(M)) u_real(.clk(clk),.reset(reset),
        .xa(input_data[(r*4+0)*D+:D]),.xb(input_data[(r*4+1)*D+:D]),
        .xc(input_data[(r*4+2)*D+:D]),.xd(input_data[(r*4+3)*D+:D]),
        .mu(input_data[REALS*4*D+(r/2)*M+:M]),
        .trace(trace_data[r*18*64+:18*64]),.saturation(saturation[r*18+:18]),
        .y(output_data[r*D+:D]));
    end
    for(n=0;n<18;n=n+1)begin: trace_control
      assign trace_valid[n]=valid_pipe[node_stage(n)];
      assign trace_tag[n*32+:32]=tag_pipe[node_stage(n)];
    end
  endgenerate
endmodule