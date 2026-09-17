// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:29:50 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t06_fs_mult_u18_s11/t06_fs_mult_u18_s11_sim_netlist.v
// Design      : t06_fs_mult_u18_s11
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "t06_fs_mult_u18_s11,mult_gen_v12_0_17,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "mult_gen_v12_0_17,Vivado 2021.1" *) 
(* NotValidForBitStream *)
module t06_fs_mult_u18_s11
   (CLK,
    A,
    B,
    SCLR,
    P);
  (* x_interface_info = "xilinx.com:signal:clock:1.0 clk_intf CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME clk_intf, ASSOCIATED_BUSIF p_intf:b_intf:a_intf, ASSOCIATED_RESET sclr, ASSOCIATED_CLKEN ce, FREQ_HZ 125000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0" *) input CLK;
  (* x_interface_info = "xilinx.com:signal:data:1.0 a_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME a_intf, LAYERED_METADATA undef" *) input [17:0]A;
  (* x_interface_info = "xilinx.com:signal:data:1.0 b_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME b_intf, LAYERED_METADATA undef" *) input [10:0]B;
  (* x_interface_info = "xilinx.com:signal:reset:1.0 sclr_intf RST" *) (* x_interface_parameter = "XIL_INTERFACENAME sclr_intf, POLARITY ACTIVE_HIGH, INSERT_VIP 0" *) input SCLR;
  (* x_interface_info = "xilinx.com:signal:data:1.0 p_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME p_intf, LAYERED_METADATA undef" *) output [28:0]P;

  wire [17:0]A;
  wire [10:0]B;
  wire CLK;
  wire [28:0]P;
  wire SCLR;
  wire [47:0]NLW_U0_PCASC_UNCONNECTED;
  wire [1:0]NLW_U0_ZERO_DETECT_UNCONNECTED;

  (* C_A_TYPE = "1" *) 
  (* C_A_WIDTH = "18" *) 
  (* C_B_TYPE = "0" *) 
  (* C_B_VALUE = "10000001" *) 
  (* C_B_WIDTH = "11" *) 
  (* C_CCM_IMP = "0" *) 
  (* C_CE_OVERRIDES_SCLR = "0" *) 
  (* C_HAS_CE = "0" *) 
  (* C_HAS_SCLR = "1" *) 
  (* C_HAS_ZERO_DETECT = "0" *) 
  (* C_LATENCY = "3" *) 
  (* C_MODEL_TYPE = "0" *) 
  (* C_MULT_TYPE = "1" *) 
  (* C_OPTIMIZE_GOAL = "1" *) 
  (* C_OUT_HIGH = "28" *) 
  (* C_OUT_LOW = "0" *) 
  (* C_ROUND_OUTPUT = "0" *) 
  (* C_ROUND_PT = "0" *) 
  (* C_VERBOSITY = "0" *) 
  (* C_XDEVICEFAMILY = "virtexuplus" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  t06_fs_mult_u18_s11_mult_gen_v12_0_17 U0
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
rMXlX/4GfxPQ8sieL1XdIZHAwFj5Fj7vIPg8gkbUo3FCqzVoROPBiS7ydd9FLLQrRf1IEU3dlJQr
8GNFX712wt/LDdYsraNkBVFsgDVdqv75dpUT+lRR6YBHFA4PRRqhCQ9Ze0Vk9HWeoMJBm3DhrCJc
AwW+vh79K/5fYAtCcZBX+wyhPkQ6iV+ZQUKkaThJ/cC1x0cZyqk2xqOTCWihmFOHJ6Dd1wjXNNyP
gj0Ix0/Gz/wLbXJ4wNXHAnF+cwxy2/oHoc6WGGrkAz7JO7guv62T9tUNW1PbLEnfmzI8uM//J8zk
cWfNx/OW7TMRI14S/BdPHile3IaxcPphwUovbg==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
xpv+e/TzNktIXyviCzm+4RakklQY55vqaUaDIp6LFtLfTZ7wBCXx0JezKzfqG7w2HFezaD34mXkC
9LZa9dWKhryIZDpErfk1gxuD15lrxziIqFlx7Exyu9wLAQbl5BxfSlLiN/dWM7sCp7UymUhO+4Ps
PTnWCnt8fGiKnSYqn0DDrsM4wlBPGBqEavSmEh3GTdQr0bW4pf8Zch3Hwlxp169Yl8tKjTZAEGXQ
SN5HirWdPjAN+IlQH7nJmm55ceqqa5ryUYv3j3EnXoGPtbF+7wbO1y7SUQSXRRc55Tif60hbWard
dmzbhlkMeFj/c9j1gUq12bubn6Pj4JAsirB49Q==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 11600)
`pragma protect data_block
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
MLyHz7TzQbc0Ph+V5PTglpsb+HsumbPBX/sN1oE=
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
