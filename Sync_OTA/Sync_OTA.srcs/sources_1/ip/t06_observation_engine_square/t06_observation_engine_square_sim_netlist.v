// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:30:37 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t06_observation_engine_square/t06_observation_engine_square_sim_netlist.v
// Design      : t06_observation_engine_square
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "t06_observation_engine_square,mult_gen_v12_0_17,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "mult_gen_v12_0_17,Vivado 2021.1" *) 
(* NotValidForBitStream *)
module t06_observation_engine_square
   (CLK,
    A,
    B,
    P);
  (* x_interface_info = "xilinx.com:signal:clock:1.0 clk_intf CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME clk_intf, ASSOCIATED_BUSIF p_intf:b_intf:a_intf, ASSOCIATED_RESET sclr, ASSOCIATED_CLKEN ce, FREQ_HZ 125000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0" *) input CLK;
  (* x_interface_info = "xilinx.com:signal:data:1.0 a_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME a_intf, LAYERED_METADATA undef" *) input [15:0]A;
  (* x_interface_info = "xilinx.com:signal:data:1.0 b_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME b_intf, LAYERED_METADATA undef" *) input [15:0]B;
  (* x_interface_info = "xilinx.com:signal:data:1.0 p_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME p_intf, LAYERED_METADATA undef" *) output [31:0]P;

  wire [15:0]A;
  wire [15:0]B;
  wire CLK;
  wire [31:0]P;
  wire [47:0]NLW_U0_PCASC_UNCONNECTED;
  wire [1:0]NLW_U0_ZERO_DETECT_UNCONNECTED;

  (* C_A_TYPE = "0" *) 
  (* C_A_WIDTH = "16" *) 
  (* C_B_TYPE = "0" *) 
  (* C_B_VALUE = "10000001" *) 
  (* C_B_WIDTH = "16" *) 
  (* C_CCM_IMP = "0" *) 
  (* C_CE_OVERRIDES_SCLR = "0" *) 
  (* C_HAS_CE = "0" *) 
  (* C_HAS_SCLR = "0" *) 
  (* C_HAS_ZERO_DETECT = "0" *) 
  (* C_LATENCY = "3" *) 
  (* C_MODEL_TYPE = "0" *) 
  (* C_MULT_TYPE = "1" *) 
  (* C_OPTIMIZE_GOAL = "1" *) 
  (* C_OUT_HIGH = "31" *) 
  (* C_OUT_LOW = "0" *) 
  (* C_ROUND_OUTPUT = "0" *) 
  (* C_ROUND_PT = "0" *) 
  (* C_VERBOSITY = "0" *) 
  (* C_XDEVICEFAMILY = "virtexuplus" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  t06_observation_engine_square_mult_gen_v12_0_17 U0
       (.A(A),
        .B(B),
        .CE(1'b1),
        .CLK(CLK),
        .P(P),
        .PCASC(NLW_U0_PCASC_UNCONNECTED[47:0]),
        .SCLR(1'b0),
        .ZERO_DETECT(NLW_U0_ZERO_DETECT_UNCONNECTED[1:0]));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2021.1"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
OWAggS0mE6JxmIlB4IqLhyMXRYPJs2DDE2a2JuZy5MB/PdXC/CaU/QRB+AqcK6JP4szhXBycSS8z
iqxQxDTUg4A3iOIyJWDbM6Yncj1VoDx+K0dqn0H+Ux6ekz1SBdoBO4EU4Q5HLCtXLJW8EgM4jzqP
00dxe67N+SsT04R4oZY=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
W60eta8irdb38mdRDzCg4GlgwIYW3/Lru9l+tJih4ChBAcKfnfaR/vOiTL+ROuIZKJnwzJcrpzmt
gvCgGzHC7YTXilcaPZwKLJGNDJz1ephChHv+dU3RVUsAD/2hTtCy4ufxwBlvovQkfC/Lj1duYn0h
OSEhgHWR+DeMUPK2qQQbBb9ABKyCPg4Lz4jFlEL0WZOm0tl9WkZ2Rm3weM0zt1B539Waq4iEp23R
cjqiwLGibXKz4dVw0e8sQSzt2A1TAWBrBGX3u9QEmYGTRB5cP/N+EuOZmOBNhHzRMDgHUduPy9IS
T0HpKpqzIIZ0OwjalMVA697TIeOPpprjIuzHBQ==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
M3QC1E4EAgFwAqgbMpRj62ZSqGtwACtMfRQvzY5xpdVjwZ2o2aUOzqn08h+DpIbitujiMLpxPUyY
lcPiiMFuzADP0+HvnkKh+nqlni8Fnu+SpjDueyH4bQJ2dEx4L2m6E/ZRMYE/21qZ+IL9Mdwhy2zM
6J4NpTA3GU+XaQ48wh0=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Joy1pwH/OfLUGgLJRqMOST5TZobooPL/KHnb20ZjYwOKq7TVLXA6nkZ+J/8E9K70lSRvS1UpSRH0
t5Xf+iolfdIIM7/OPQhbsr7sGEWHdc0Q64eg+2GGAtSF2BZhsT705w77/DIW4nJKkUpC+VtMtRti
4i/AZB4v3m63KchVydIiWT2eypZaOcJdUaYuq7w3OS5NU1piGksgHh5Xb+szulbvxqFKE4Euv4Yx
O7uUo/+9PH/CzsgmGmKDh2HAp7VMhCk1Hmog74d7Pl7wyr3Y4dBrBBjw1c9mS9qqLDPt/gNTlehB
iOvhgs2sgiqrvmfcmcjLfXJB/a6mYZAOTPKzdA==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
g5GY+ruVbJTSNLBZAxKMjzWHqiIBBFLVm0mTIk/27vAJCn/7qN2eNybonN/BbLo0bhsIPnygWtUL
HnBzb30j9hTIkOmb4h3ghEtCopb8bWgen8W+K7lAXMMqSm7UP7SZS+oM+10KcJe73JRSORmhfQmO
1F9OJcu1SAirUVlJoJqHPQM+dVcXzqk6Cy0tnQfjOZzeDPrV6KdMtxexq8eq6tFX+nHwbh71bmwl
4OMHzfEhBHHlRAUDFfsH8FYwkZAH2dnFSqcyb8m+vXobKB4O1tVszhDIgza9r+ofijta9/KCeReP
oi5b+rs6mP4QE2kKqCEN3629NW5mbzUug9MxiA==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2021_01", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
HNsfBze5a6QtwiAVnGLfFdHHbrU0Oi1c4+CJlHFAOZfXnXZ/b0aEkATWnGGXfvTJAl/Vcr9Whmt+
ekNOhMdu6oXKJ+MJfm2u2jzE3biF+Xa2B9OUw2cnR3sWidPCSfrg1AS5LI2BdlfVD335L8jMJwSV
9dfiE+IthObOKpmZsPiY8zMjdsXwLNxi03pCI8Xly1WwfwvnPHx8W9QTlilHJGrd8NoS1J4RBmrZ
V4U7cpvPr5rFlz0kaBhufye7oY6yr+YRvjdzygxJ9Is4LecDDaRMF4r1PTAtwheEd5a3Fpb6OLzb
12VR4H77zZWEihgmoRyssQ/RlLdENnMf74PhDA==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
qajdWELb7xq5MRKDXqbY5G9KalZ6KvS/OFspNPgehavTLyCjfNFwOe7rD6u4OQ9DhpFj21XMOcHT
4IpirpdyiIXOWlDbI0L7UF7fg+oZhywH/4zzeLjKZ1VuNWMxku8tJIciokgfgS0Rc5zJRkFE1fFh
XqKbA8o5V2On2ZWFsxXRHCowiAVXpEbk4hoxIV8L5vuYfM+LmEAQrfNmzVr7ggxMKIAYY8HGsD5y
y68JxstiU/xG1rcmnjRIdeZIHXXBRuFGZjouuAthvqQCk4Aqa0dBLg1Pa5bvF8xwe+FNLdELWLsI
p4Imohkk8nqjgLE5kfHUvK6lNSUTJIGtfR7lWQ==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
G99JGOPeAWEzvhKOQHBjIJBTWpBqc6eHcwpnoconyJGsCO3rY4RPzw0sPWdTfUbZVf28/xzMdMAw
5Bl0VSYMJ3cfG3uenDKsZF2v9KBin+XsJwfKWs/gxK9A2D8qVJQyLd4ION84axXVPxfI5Gzv2FIm
d2V4C4p5YxpnLiGdskIrPJ2AAa4yZEeWuN01HCD/W+H9Ca3vsRn+2VmFDJbOHyec2GOMH66evWmZ
AlFNPDQSwT+6TVCHFXgpOYsFwwIg3mVZl2EBK7oPx1QESXZOnOLee+VELSumkJOFUI2v3kGFm4+2
yANu0tMCR+Ch57FICMokLG1y7s0yZ7DCuokjx1SKM3Ap/yHSSjBMyE6cOAjHL+oF9ZHdDbGV5v0U
s6Ses23kmJMCOcHQDKgORHBaU5DaZgcdobyCs2MMkJo9CarOL4u/Feim00de/2xjgBS0jQPmVxYI
DV5Y6z4b2qpXJD9yvkwweqY8ZifrG3dHasuUscjtRiYqbLIMonADOsos

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Yg8e7EeHtxErkKZVvi6QJXJCvHzYThtbtZDWYWwhr0hMZCh7wlRPMUDcoEsUXREL9HKBlNIU/8Ip
RFJXEQyG4fzyXOfxoqTV5aFAlBcJbbBITUlrf6b/PM/ef8SPakuJVxDFuGpznAfWV7MaQwD4pGCi
1hZVmFLCjiNVZ/pcZslIeU1yCGclZYjf4Ru+ChXq4zcRuRDybOhAnvOk6/sQJZHGiDiA/H5Lghki
plk50q2/VS4rx+xPeNogEvz/tKK3mUhK/3Sx0BqDTR9u+8Ltxs+0gK55oKH0CNj0HtBdvVId3fDy
w5WvPz8SmltzhMCYDtDP+iKXf+EKR9m/Co0FQA==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Jb43zWIUxAhQcuDThZsOA9KVE8jhQlXAM8mefCAFdS//8w1BKKHi8QsY6NExtpyFG6G2y6HlZokj
CbOLjJYImIsthnW5J3+c3sSFfFgpr8K7ubxxtrrOtunJFg7oVLdvG+0+oKmmMW+sGPHlWt45x7ql
Tz4aw2gJPOeJFA3p5qGyA2t/W4KUDGkB9vaLECr7uVL2mDJzZxJjGg7oj6SDjjvN4kyEFcvK/Z6r
hxpuZ1UfF80PfOaJnp81TPHnTa5O7G8pZrmhTsVCEwvjSp0YUg9zJcpe1s5O6Cm/0RZr/uHhbGuo
8KcbRCt/mQR0CEnfm5QHJVD1cY/Agsp9DzWqcA==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
djN0O7Wvqzbdg3G4u38gFI0iVycBfSRjN0TpOEX3YCCgSxHWoYB9apX4SM4d1iC7ND5OnTWyqlOI
oLGfRGN4UXMiDxS38BYXlZQKGBVtZFO6GXq0al8DX9xp+ICQ7gwDACJNxyzgw976DbYr8p2g0lhG
NRA3LKFBpfSSBdhFUmxWOjMMIgb19RFiYWcytq0GX4C0+bAqM7K+RI9MatghD5gugS8ojm+16y6I
babvcJ+y9iwxTHjCmQmZinFM0C+swv0GN97lCj6xhXVHSGoU7WHonmjTSOz1f0xRpysP/KyJvfOM
76VEfm+xq8EIO5+KlSIJXeXnHNbfA62+HQbDng==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 11552)
`pragma protect data_block
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
`pragma protect end_protected
`ifndef GLBL
`define GLBL
`timescale  1 ps / 1 ps

module glbl ();

    parameter ROC_WIDTH = 100000;
    parameter TOC_WIDTH = 0;
    parameter GRES_WIDTH = 10000;
    parameter GRES_START = 10000;

//--------   STARTUP Globals --------------
    wire GSR;
    wire GTS;
    wire GWE;
    wire PRLD;
    wire GRESTORE;
    tri1 p_up_tmp;
    tri (weak1, strong0) PLL_LOCKG = p_up_tmp;

    wire PROGB_GLBL;
    wire CCLKO_GLBL;
    wire FCSBO_GLBL;
    wire [3:0] DO_GLBL;
    wire [3:0] DI_GLBL;
   
    reg GSR_int;
    reg GTS_int;
    reg PRLD_int;
    reg GRESTORE_int;

//--------   JTAG Globals --------------
    wire JTAG_TDO_GLBL;
    wire JTAG_TCK_GLBL;
    wire JTAG_TDI_GLBL;
    wire JTAG_TMS_GLBL;
    wire JTAG_TRST_GLBL;

    reg JTAG_CAPTURE_GLBL;
    reg JTAG_RESET_GLBL;
    reg JTAG_SHIFT_GLBL;
    reg JTAG_UPDATE_GLBL;
    reg JTAG_RUNTEST_GLBL;

    reg JTAG_SEL1_GLBL = 0;
    reg JTAG_SEL2_GLBL = 0 ;
    reg JTAG_SEL3_GLBL = 0;
    reg JTAG_SEL4_GLBL = 0;

    reg JTAG_USER_TDO1_GLBL = 1'bz;
    reg JTAG_USER_TDO2_GLBL = 1'bz;
    reg JTAG_USER_TDO3_GLBL = 1'bz;
    reg JTAG_USER_TDO4_GLBL = 1'bz;

    assign (strong1, weak0) GSR = GSR_int;
    assign (strong1, weak0) GTS = GTS_int;
    assign (weak1, weak0) PRLD = PRLD_int;
    assign (strong1, weak0) GRESTORE = GRESTORE_int;

    initial begin
	GSR_int = 1'b1;
	PRLD_int = 1'b1;
	#(ROC_WIDTH)
	GSR_int = 1'b0;
	PRLD_int = 1'b0;
    end

    initial begin
	GTS_int = 1'b1;
	#(TOC_WIDTH)
	GTS_int = 1'b0;
    end

    initial begin 
	GRESTORE_int = 1'b0;
	#(GRES_START);
	GRESTORE_int = 1'b1;
	#(GRES_WIDTH);
	GRESTORE_int = 1'b0;
    end

endmodule
`endif
