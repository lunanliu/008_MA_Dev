// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:23:53 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/farrow_mul_t16/farrow_mul_t16_sim_netlist.v
// Design      : farrow_mul_t16
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "farrow_mul_t16,mult_gen_v12_0_17,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "mult_gen_v12_0_17,Vivado 2021.1" *) 
(* NotValidForBitStream *)
module farrow_mul_t16
   (CLK,
    A,
    B,
    SCLR,
    P);
  (* x_interface_info = "xilinx.com:signal:clock:1.0 clk_intf CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME clk_intf, ASSOCIATED_BUSIF p_intf:b_intf:a_intf, ASSOCIATED_RESET sclr, ASSOCIATED_CLKEN ce, FREQ_HZ 125000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0" *) input CLK;
  (* x_interface_info = "xilinx.com:signal:data:1.0 a_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME a_intf, LAYERED_METADATA undef" *) input [16:0]A;
  (* x_interface_info = "xilinx.com:signal:data:1.0 b_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME b_intf, LAYERED_METADATA undef" *) input [9:0]B;
  (* x_interface_info = "xilinx.com:signal:reset:1.0 sclr_intf RST" *) (* x_interface_parameter = "XIL_INTERFACENAME sclr_intf, POLARITY ACTIVE_HIGH, INSERT_VIP 0" *) input SCLR;
  (* x_interface_info = "xilinx.com:signal:data:1.0 p_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME p_intf, LAYERED_METADATA undef" *) output [26:0]P;

  wire [16:0]A;
  wire [9:0]B;
  wire CLK;
  wire [26:0]P;
  wire SCLR;
  wire [47:0]NLW_U0_PCASC_UNCONNECTED;
  wire [1:0]NLW_U0_ZERO_DETECT_UNCONNECTED;

  (* C_A_TYPE = "0" *) 
  (* C_A_WIDTH = "17" *) 
  (* C_B_TYPE = "1" *) 
  (* C_B_VALUE = "10000001" *) 
  (* C_B_WIDTH = "10" *) 
  (* C_CCM_IMP = "0" *) 
  (* C_CE_OVERRIDES_SCLR = "0" *) 
  (* C_HAS_CE = "0" *) 
  (* C_HAS_SCLR = "1" *) 
  (* C_HAS_ZERO_DETECT = "0" *) 
  (* C_LATENCY = "3" *) 
  (* C_MODEL_TYPE = "0" *) 
  (* C_MULT_TYPE = "1" *) 
  (* C_OPTIMIZE_GOAL = "1" *) 
  (* C_OUT_HIGH = "26" *) 
  (* C_OUT_LOW = "0" *) 
  (* C_ROUND_OUTPUT = "0" *) 
  (* C_ROUND_PT = "0" *) 
  (* C_VERBOSITY = "0" *) 
  (* C_XDEVICEFAMILY = "virtexuplus" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  farrow_mul_t16_mult_gen_v12_0_17 U0
       (.A(A),
        .B(B),
        .CE(1'b1),
        .CLK(CLK),
        .P(P),
        .PCASC(NLW_U0_PCASC_UNCONNECTED[47:0]),
        .SCLR(SCLR),
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
LhJL6Etjg9PcpPn/lXSpzXSTBCfytz0awH5qWA8713JwF9J1sGzi0AZh5aWSn6/mvi31CgvpzgP6
I72TWnuo9FIPSc6zvAXeNnZ60eC99RAamNoe3IFbjle473wDOliQct2vyxH/GwBGhOsTAJLLcVW+
lozucSTOeq0RywB4CsYWHASwuTDuTHN7e5938KZkRouKorbmeJxQSWpfg2YFTTAiZGBl2S3t8Ji2
r2vZlM80CgPAgBrBWVAWGLkql3evIgTuFC1ktZUbvAbzJ8lBLww4NtQwgNCTiOcv0lB+WypKe9pI
qXaC0zV/ADnLQ305hn/SUoUUSCcxNXjyHe/nkw==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
wirtfziY2SYC/OKBjeRwksetYahc5gRIsYMSSO3gCa7P4ysOYSllxYtEwO211BsmUj5XWMKk6QUB
6W9Jc70bNQXFes/CSwsndE1txLIjtspBBLrBMA8if7aOKmkQrputzTzPexnX147XNJuNuc7uVCMJ
0eU4S+AgRfC4pVA3yKFmeV6TfkGDOSS+g3XV72Ym7aGzmGYMlF24L+btC8QHg+E3YKmUnl6B5AXm
Z39CO+g4ESKsXAWAm34DmogGw79UPmCDAqMgOS0YjAjh452E8nH1/rUQLFCaSBRoBEOdLgNCVonR
cqFg84TqhSEJ0TyPROFVWkksvEV7Hx4nH9xkZw==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 11584)
`pragma protect data_block
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
vKIbVyHHnMcNqiK5Sw==
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
