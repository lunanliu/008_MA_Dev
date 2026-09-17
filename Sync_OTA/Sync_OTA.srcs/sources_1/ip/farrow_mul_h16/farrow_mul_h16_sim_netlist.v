// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:22:51 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/farrow_mul_h16/farrow_mul_h16_sim_netlist.v
// Design      : farrow_mul_h16
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "farrow_mul_h16,mult_gen_v12_0_17,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "mult_gen_v12_0_17,Vivado 2021.1" *) 
(* NotValidForBitStream *)
module farrow_mul_h16
   (CLK,
    A,
    B,
    SCLR,
    P);
  (* x_interface_info = "xilinx.com:signal:clock:1.0 clk_intf CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME clk_intf, ASSOCIATED_BUSIF p_intf:b_intf:a_intf, ASSOCIATED_RESET sclr, ASSOCIATED_CLKEN ce, FREQ_HZ 125000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0" *) input CLK;
  (* x_interface_info = "xilinx.com:signal:data:1.0 a_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME a_intf, LAYERED_METADATA undef" *) input [18:0]A;
  (* x_interface_info = "xilinx.com:signal:data:1.0 b_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME b_intf, LAYERED_METADATA undef" *) input [7:0]B;
  (* x_interface_info = "xilinx.com:signal:reset:1.0 sclr_intf RST" *) (* x_interface_parameter = "XIL_INTERFACENAME sclr_intf, POLARITY ACTIVE_HIGH, INSERT_VIP 0" *) input SCLR;
  (* x_interface_info = "xilinx.com:signal:data:1.0 p_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME p_intf, LAYERED_METADATA undef" *) output [26:0]P;

  wire [18:0]A;
  wire [7:0]B;
  wire CLK;
  wire [26:0]P;
  wire SCLR;
  wire [47:0]NLW_U0_PCASC_UNCONNECTED;
  wire [1:0]NLW_U0_ZERO_DETECT_UNCONNECTED;

  (* C_A_TYPE = "0" *) 
  (* C_A_WIDTH = "19" *) 
  (* C_B_TYPE = "1" *) 
  (* C_B_VALUE = "10000001" *) 
  (* C_B_WIDTH = "8" *) 
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
  farrow_mul_h16_mult_gen_v12_0_17 U0
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
CV2888RqRW+H3ODrb+t6XMaKomc6+8MLLZsG84azxhwWkiJg5T/OYufyzxlFmLgCtFpM5PH8kd83
gWDgT92WWqVbqm+dkcGzf9JuQDpCKQY7kIoPuJ/Mm7SHzpsrXRerM6PmlyLnXjHCzYBFl9yM9eZ7
aECzXQzUdVbLQNw5lrvKJaD/wGO4jHvvJpLgiI01JXfCWwa/DdTE0GvlzOLdvnHH94zU4g9ka9E5
tiE7vtze+uCmV549zWAlicqMfrPU2lZqamXbaVGvrtaawrai57rsmEHCK0M+RFZJH7lcLijQMumc
UXzs/1+NtAaH8FwS5/BvwVcHld7mxESgDcmceQ==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
yPVhoKBweRWjzrjDoIo54UfO2hLpU3bL7j8SMY7DkJRffxqgnCKMwSpimLRi42JqN/S//LIKPnnz
GySr8aPUsjq+LBlDnkrngGnm/KPdofxPB8RRFdjTc7dteh4AksjkuzStAprYPD03Nn+K3qWpVSP4
6U7HqJQ4o/psglYGXT344AIsx9eIUUw7ukgkAlK2khaBA1Tf28zj1DJ7JJy3BFMItMx8I9XGfnXa
ydV3RlKZF4WEIxiBdm75Dq9+OBWXcEYUafIg1CzTTG2WXcjE3+COIkJ1+H6YjSI1wJqmZsHiUG0o
u6FxC5+yOzi+LPkEDRi/uUmGtcQgOP3B1Av/rg==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 11584)
`pragma protect data_block
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
WY4NMe8tXktvIc6pBQ==
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
