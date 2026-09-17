// Copyright 1986-2021 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2021.1 (win64) Build 3247384 Thu Jun 10 19:36:33 MDT 2021
// Date        : Thu Sep 17 04:22:50 2026
// Host        : ROG-Lunan running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode funcsim
//               d:/008_MA_Dev/Sync_OTA/Sync_OTA.srcs/sources_1/ip/farrow_add_18/farrow_add_18_sim_netlist.v
// Design      : farrow_add_18
// Purpose     : This verilog netlist is a functional simulation representation of the design and should not be modified
//               or synthesized. This netlist cannot be used for SDF annotated simulation.
// Device      : xcvu11p-flgb2104-2-e
// --------------------------------------------------------------------------------
`timescale 1 ps / 1 ps

(* CHECK_LICENSE_TYPE = "farrow_add_18,c_addsub_v12_0_14,{}" *) (* downgradeipidentifiedwarnings = "yes" *) (* x_core_info = "c_addsub_v12_0_14,Vivado 2021.1" *) 
(* NotValidForBitStream *)
module farrow_add_18
   (A,
    B,
    CLK,
    ADD,
    SCLR,
    S);
  (* x_interface_info = "xilinx.com:signal:data:1.0 a_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME a_intf, LAYERED_METADATA undef" *) input [17:0]A;
  (* x_interface_info = "xilinx.com:signal:data:1.0 b_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME b_intf, LAYERED_METADATA undef" *) input [17:0]B;
  (* x_interface_info = "xilinx.com:signal:clock:1.0 clk_intf CLK" *) (* x_interface_parameter = "XIL_INTERFACENAME clk_intf, ASSOCIATED_BUSIF s_intf:c_out_intf:sinit_intf:sset_intf:bypass_intf:c_in_intf:add_intf:b_intf:a_intf, ASSOCIATED_RESET SCLR, ASSOCIATED_CLKEN CE, FREQ_HZ 125000000, FREQ_TOLERANCE_HZ 0, PHASE 0.0, INSERT_VIP 0" *) input CLK;
  (* x_interface_info = "xilinx.com:signal:data:1.0 add_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME add_intf, LAYERED_METADATA undef" *) input ADD;
  (* x_interface_info = "xilinx.com:signal:reset:1.0 sclr_intf RST" *) (* x_interface_parameter = "XIL_INTERFACENAME sclr_intf, POLARITY ACTIVE_HIGH, INSERT_VIP 0" *) input SCLR;
  (* x_interface_info = "xilinx.com:signal:data:1.0 s_intf DATA" *) (* x_interface_parameter = "XIL_INTERFACENAME s_intf, LAYERED_METADATA undef" *) output [17:0]S;

  wire [17:0]A;
  wire ADD;
  wire [17:0]B;
  wire CLK;
  wire [17:0]S;
  wire SCLR;
  wire NLW_U0_C_OUT_UNCONNECTED;

  (* C_AINIT_VAL = "0" *) 
  (* C_BORROW_LOW = "1" *) 
  (* C_CE_OVERRIDES_BYPASS = "1" *) 
  (* C_CE_OVERRIDES_SCLR = "0" *) 
  (* C_HAS_CE = "0" *) 
  (* C_HAS_SCLR = "1" *) 
  (* C_HAS_SINIT = "0" *) 
  (* C_HAS_SSET = "0" *) 
  (* C_IMPLEMENTATION = "0" *) 
  (* C_SCLR_OVERRIDES_SSET = "1" *) 
  (* C_SINIT_VAL = "0" *) 
  (* C_VERBOSITY = "0" *) 
  (* C_XDEVICEFAMILY = "virtexuplus" *) 
  (* c_a_type = "0" *) 
  (* c_a_width = "18" *) 
  (* c_add_mode = "2" *) 
  (* c_b_constant = "0" *) 
  (* c_b_type = "0" *) 
  (* c_b_value = "000000000000000000" *) 
  (* c_b_width = "18" *) 
  (* c_bypass_low = "0" *) 
  (* c_has_bypass = "0" *) 
  (* c_has_c_in = "0" *) 
  (* c_has_c_out = "0" *) 
  (* c_latency = "1" *) 
  (* c_out_width = "18" *) 
  (* downgradeipidentifiedwarnings = "yes" *) 
  (* is_du_within_envelope = "true" *) 
  farrow_add_18_c_addsub_v12_0_14 U0
       (.A(A),
        .ADD(ADD),
        .B(B),
        .BYPASS(1'b0),
        .CE(1'b1),
        .CLK(CLK),
        .C_IN(1'b0),
        .C_OUT(NLW_U0_C_OUT_UNCONNECTED),
        .S(S),
        .SCLR(SCLR),
        .SINIT(1'b0),
        .SSET(1'b0));
endmodule
`pragma protect begin_protected
`pragma protect version = 1
`pragma protect encrypt_agent = "XILINX"
`pragma protect encrypt_agent_info = "Xilinx Encryption Tool 2021.1"
`pragma protect key_keyowner="Synopsys", key_keyname="SNPS-VCS-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
GTqSEFfdw74AxDk1xtNQd2f6GHWzPN2yfLbDluzXTaZpl4W+sEd4lTW79qJytbO6Id+EKMIQA/Rd
JoOZOfWlzssuRG26ui4Pta5Y3JPgDAy22thMZez0bbLCexUp/MGwpsqeiAH6fB25CKwqaY0ZeWU5
zVSIuMCwrJjkXNKwtns=

`pragma protect key_keyowner="Aldec", key_keyname="ALDEC15_001", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
Zg7QdpS0h5qvdN8jDF6+Uy7LIqhoofwxBC4VSN6My9UgXglQ2uXgzJ3C3R8F1pgtGLa4D+ow2y/Y
AYpFHE8foILr6fC+wuHZ1AVOCIwn3jyrqkyC5GdfavPR782wRbs37sC/s2HdBL9KBYEYx/5Jns/o
UYIX6hvN50LZfVhiFW7hgfl90zqrt0dD0p5PPQIo+CjylU1iskxRQklRTt4e8CiQG4CDFV4P8lOl
A8j9h1MbVgW67VZNE2bmg8yVzCpLZWRMG/YJVq4c5A6ijn++/Skhq8nBHcw/pDZM2cPEt5tIjCsi
RX7+h5VqjxnJIDLE8NjzHmZqaYqo0f46F0d8yA==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VELOCE-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=128)
`pragma protect key_block
sraMSTIusw2vW8x6E/6NjBaBni1BYS47l8DJ4rLdHpjUsGIjJyCpbYaL5fGuk9CxeqtrDOjYVAi7
90gKBWdO9PFhDW1ioDW5KOAL0Vn4jIu47pX4jDV4qeNvNk1diz69p4CFg1STDlAXZzrSuxsj72WP
87dmE4nl3SabfGRMBlo=

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-VERIF-SIM-RSA-2", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
DR1bpsHn3evUQJqCy4fwFjV86IgidayNbMB9OsXIxw3etzwha87Cnp5nA00lGLG4fZ8pZJyrI6L/
fRkMyndVySdfcAKVuezHlGOupplByaJ1+yCRdSsxFWClOxzxu14UG4YKPeaiNLetLoWeelB5Tnqq
1hYi/BGV/rThTOY71pF8la+OJtDpWMFLfoXJoOTVCegrm5gqKtFY6w/8XsbGVdyg3iSIqj8qCkwB
BZ3YsrUv1TDfRwq1TYRCI1n8zXr53wvSW/5PP77E4inmNHCXCVXnOKsizHIZJAkA2UmS1vzkurzr
VEW+C/svU60NnxjcTMNcwEEDircH1H9DE6aBOA==

`pragma protect key_keyowner="Real Intent", key_keyname="RI-RSA-KEY-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
mOBk7oA7/Fcn9XTT8ZhbYFKmYzC49P630wnSr28owJKgc5uh27BumG9Lb7w3/r45RWv2mmSUb6eo
4mxciLVWSDIdLhjlTf7LOhgrJMOQXh5LGfsh9zwms2iOvCnCe0hfP9CL4UIgLUV2jp5cxrFr9uAh
yJgNcg2fWFX83mbc16nw5NIp0rSQlbrOKf65j+6+CDDgfV9oxBoALy3cgRDvV7+fgxQgopIKdFoK
b45HIQkxV/IjqDH03Avy68Ukar+0zNvwBgy+ehioNpAXVylHbDXnHQp4PrgZSO+OktFUy+3UBAwI
dJq7YaBh/R/fv/SlpxdK/xa4Qvtzq9l/9JB4GQ==

`pragma protect key_keyowner="Xilinx", key_keyname="xilinxt_2021_01", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
bCy2E+cIonplnhEbZmGvC1heHQ60MGwVmU2x15ENdnJuhBjqhnJc/OjcmXCnsQ0PVFLIlQ/0wpvC
IqfKU1GFE+M+qT4h4wnc/x1JQXagKtMY5JeKKAYfWs8npp6CsE1Cg65poSjyPQsgppvcKCQkY5IZ
90pVE9LqdAo5VyBUFrKhK+FCFJMU+3N2xsv05aL9/AGTNG+GXNZ7CkLFnRb50dABLQ4Ku2BMSRvn
+UuVYirvcztxNT1gNuOrcoLmom1iYxT/TCqIeQROkp5HGgunWatU6fYC+ht+UFU9ygjggNSGfAnd
nCf+NSTYx33GxKIYVtgmZXwyP5cI8Lk/NmSxwA==

`pragma protect key_keyowner="Metrics Technologies Inc.", key_keyname="DSim", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
TmV0I8CXrLN6NcEG9hNmTThTTkBIattb9yt7bm+0yRK6TSd3xiYqQWx5SXI3IMOAAqoYeCKDQiZi
cDQjcnh57glJKKvIBsctOLK/D2Kxyx3ml4Bjudc5vHfUEcBa5y/gEA0EWGBeWkllUdY84GtJEUsS
AuoWUgMw5h5ipQAj5iVYp95KGgk8eW8+W7GSh8cLYOV/kSvykcQxSrHFcgdJFnmCjN2aBEVI+6Rq
fnZfZDbZGAJB6fq14VDxtFeZczuf+wg4xmxBX+Eh2/eWWs22Kj7qYMcbKvAFaRq5iGeydCuQBnIu
ea3TVf+OoBqLQ94kHgaoWr2qD25EKHXRIXHKzQ==

`pragma protect key_keyowner="Atrenta", key_keyname="ATR-SG-RSA-1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=384)
`pragma protect key_block
Qes+skSjlfcngFHqOonb/14mf4z1xOJPJsFQklrcQMwgfeYnzbXPyi+VjQno7oMepbwl3h4WW5qp
aNXYP/ZpN4wr42OVgYVRglpc1gbAeMcellSFa1b3aa0p0MTVbZLuSRBHvAHGATaSH+IryuDZhdQK
2ph4EVLTnZlFXUBQTpyMiG7KQBeQ0fae3hCn5gCL5DSdxeRA3jjvxvbhmrKdOJ62//GfreJsyaWw
nYXtlk7UFCVSSNpAlj6KeazG3ySpvsPARbSw7rVBZlwuxyyVaNShIrT4xyocuG+decy0RByiaxY3
VVhRV6XM/SqfxlhSmSAQ5c9iR+Z7Of4EW3OPW3xuRiFX3j2RMmv7RZJ+grM24tWBNfD7vubT/uYx
LHeqF03tFF/s6jlupPE6Ss6Jdt/rNxPq1rM10viJa0v0aNFc/a7FhHHO9CmpZ3V18zUmudbd6mIi
itL0+u9Q5BeihF1Yk/zHxWnMDZ9bzZzebHRLl4tGiWOJMHyTnvLtg/uj

`pragma protect key_keyowner="Cadence Design Systems.", key_keyname="CDS_RSA_KEY_VER_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
fT9P0busnHFhNtVhuf1ATqDeNMlqjQwbhvf0x34wZd35mjARDv55SXpRz+pBacoaxyo8g70Zt6by
jhGGO95tzsD9Cq8TIfsQ2B4hmI5lT4QzHGYby6xuklbwvPhpcpNgdDV9apT+gdvPWZnNk+R5awyV
uNxQNzyZblMxkJinicsdHysCQjzYlps9O1mEE9ZZTZ6WH4+e+k1mrmPmUBBazuWMZ2/cw7t9XbZT
/zm9meBtxtVaA35lu3qeM0Of8DV+54hnAG4sYgN9RRwmHgxE//V5fc/cyV6/fVWSrBIACq6lNplr
Gs0JTuAQrPaxxhx39ruQXEKIuc1vtVdzAuNhSw==

`pragma protect key_keyowner="Mentor Graphics Corporation", key_keyname="MGC-PREC-RSA", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
cOF/lIVa5FFbdmEowzZeJUDfDRDl+wz9hC7GZbKbQtEMnzZ+mNsliAh+jtMEjY3BmZ6yCQogt13v
MpGGEoEbkKJnhc09ADv9D5bT/ii5HfgR5mlVzPpGEGELIQIvsGH9IDEs4hvNxAa5vlsK+4DzFx5J
AS0CCdt2xIar+MmhGxx/fUEe4Su0b1LIHN31C9p0crY72uGXebblzb72XSWrxdVlDzGAmZU2cG9i
ekA4XRxQmk2W7kwjWRyJqApBud76wN+vr7pPJZqqU+ImK4SukUNpdVzycxoZlwLUNEe/7aShmRe6
37M8CYOLoparsCT3vt32lSAzNaHSwbU3AiceRg==

`pragma protect key_keyowner="Synplicity", key_keyname="SYNP15_1", key_method="rsa"
`pragma protect encoding = (enctype="BASE64", line_length=76, bytes=256)
`pragma protect key_block
IgnZOcVOWzVMLk3axaAFDWEzzoVSl2w4MTsA2YTG3NLcbYFqLsmu0NvyDQPe9qne5Wkgnt/5WbSk
GWqHF8VWoaG+Zl9YgpT0p8lW3s93uh6aOy89bYFXxTD2G1RVtTicHGB79Y8huTMabkOWmOxqkt6j
idaDt3ce3bjxQxfur5UYEJV0tVeKPgabAJpVfzbQBtFS23qGkdNinK4omfXWlI9L5HsiF+q9T/Qr
MvtmKP2Gw8po1pCjNC7+gkizzaWUgwKLxEBLB3jPSPp/oCmpIkWppG8lZs5Z5sj9M8ShhWUy9Hw9
9VHrQnXGYKLzOL4roFvqB3VC9QpdWzUTIvpOTA==

`pragma protect data_method = "AES128-CBC"
`pragma protect encoding = (enctype = "BASE64", line_length = 76, bytes = 17184)
`pragma protect data_block
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
byJYxqEUQfAq9RYEWS5HWgcpIrDQtR/OjyfP
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
