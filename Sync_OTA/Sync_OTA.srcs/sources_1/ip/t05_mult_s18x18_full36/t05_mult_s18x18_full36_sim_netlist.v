// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:24:47 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/t05_mult_s18x18_full36/t05_mult_s18x18_full36_sim_netlist.v
// Design      : t05_mult_s18x18_full36
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "t05_mult_s18x18_full36,mult_gen_v12_0_17,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "mult_gen_v12_0_17,Vivado 2021.1" *) 
(* NotValidForBitStream *)
module t05_mult_s18x18_full36
   (CLK,
    A,
    B,
    P);
  (* x_interface_info = "xilinx.com:signal:clock:1.0 clk_intf CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME clk_intf, ASSOCIATED_BUSIF p_intf:b_intf:a_intf, ASSOCIATED_RESET sclr, ASSOCIATED_CLKEN ce, FREQ_HZ 125000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0" *) input CLK;
  (* x_interface_info = "xilinx.com:signal:data:1.0 a_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME a_intf, LAYERED_METADATA undef" *) input [17:0]A;
  (* x_interface_info = "xilinx.com:signal:data:1.0 b_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME b_intf, LAYERED_METADATA undef" *) input [17:0]B;
  (* x_interface_info = "xilinx.com:signal:data:1.0 p_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME p_intf, LAYERED_METADATA undef" *) output [35:0]P;

  wire [17:0]A;
  wire [17:0]B;
  wire CLK;
  wire [35:0]P;
  wire [47:0]NLW_U0_PCASC_UNCONNECTED;
  wire [1:0]NLW_U0_ZERO_DETECT_UNCONNECTED;

  (* C_A_TYPE = "0" *) 
  (* C_A_WIDTH = "18" *) 
  (* C_B_TYPE = "0" *) 
  (* C_B_VALUE = "10000001" *) 
  (* C_B_WIDTH = "18" *) 
  (* C_CCM_IMP = "0" *) 
  (* C_CE_OVERRIDES_SCLR = "0" *) 
  (* C_HAS_CE = "0" *) 
  (* C_HAS_SCLR = "0" *) 
  (* C_HAS_ZERO_DETECT = "0" *) 
  (* C_LATENCY = "3" *) 
  (* C_MODEL_TYPE = "0" *) 
  (* C_MULT_TYPE = "1" *) 
  (* C_OPTIMIZE_GOAL = "1" *) 
  (* C_OUT_HIGH = "35" *) 
  (* C_OUT_LOW = "0" *) 
  (* C_ROUND_OUTPUT = "0" *) 
  (* C_ROUND_PT = "0" *) 
  (* C_VERBOSITY = "0" *) 
  (* C_XDEVICEFAMILY = "virtexuplus" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  t05_mult_s18x18_full36_mult_gen_v12_0_17 U0
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
Y8DHejVltnUvHrUsScg1q7vqy0h50cKNPZDt6pxNTkeBFIl6wfHjZ3dGuexVkTSDj6OgETIjak50
Fh6BejWqo6O3LWuMVOu2ahbmIOX7/cb3vZNHHmFukACkLTzm0E44KeCTf+nDHqxloGJ9iWaXpggz
tTbjrwb2+Feaf2oggMDbB20IU2pLNHsRcc9rS6i2pOCoa1+cPXl8sDinzI4dJbf4jHth7WDKM+52
LB61hfzYB8cdjmEeHzYucZmFlO0ucfBLxLOlReuh1NBxE2cbNidO3jslGNUOjyvHao3KuqnGMT+j
p+MMk6m13HpJd6V1iWZQ9RW19z88hrf/hwtRzA==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
fQQA4Tn9w9mle5NV3LCwF9QmIVyncPu3qSCVekYnBpMVw2ovBO5K8XRkutjr5DZvsPKrfQuicTXe
MYhk6DON8Yh8bDAR1iTr172xtCSFhOv09mhK5Ch1a3vKSTmQlkiczNZ3dHos5yapYwm5UgAfST+Y
CGKuFp7hax5R/cFX7gC9GUYU1BaZ1vNMQfQQdNcRXuYQ8VYCbXVtFXokjFGbXuhr1PkDzUOiCXz2
UKti90k0oluRl/R5J9xJGngncTJ3GGDmFqVMtfibcCdQ7CzXmSUZ9kEvbOOKXMiq0RJAqIfNWVM5
tuQrNR7U36GTG0Op3qWzPE0iLz5Cpw04bdQ7vw==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 11504)
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
