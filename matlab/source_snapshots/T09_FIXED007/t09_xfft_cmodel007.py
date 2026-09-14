"""T09 local bridge for Vivado 2021.1 XFFT 9.1 official bit-accurate C model."""
import ctypes as C
import os
from pathlib import Path
import numpy as np

class Generics(C.Structure):
    _fields_=[(n,C.c_int) for n in ("C_NFFT_MAX","C_ARCH","C_HAS_NFFT","C_USE_FLT_PT",
               "C_INPUT_WIDTH","C_TWIDDLE_WIDTH","C_HAS_SCALING","C_HAS_BFP","C_HAS_ROUNDING")]
DP=C.POINTER(C.c_double)
IP=C.POINTER(C.c_int)
class Inputs(C.Structure):
    _fields_=[("nfft",C.c_int),("xn_re",DP),("xn_re_size",C.c_int),("xn_im",DP),
              ("xn_im_size",C.c_int),("scaling_sch",IP),("scaling_sch_size",C.c_int),("direction",C.c_int)]
class Outputs(C.Structure):
    _fields_=[("xk_re",DP),("xk_re_size",C.c_int),("xk_im",DP),("xk_im_size",C.c_int),
              ("blk_exp",C.c_int),("overflow",C.c_int)]
class XFFT:
    def __init__(self, vendor, maximum, runtime):
        self.dll_dir=os.add_dll_directory(str(Path(vendor).resolve()))
        self.gmp=C.CDLL(str(Path(vendor)/"libgmp.dll"))
        self.dll=C.CDLL(str(Path(vendor)/"libIp_xfft_v9_1_bitacc_cmodel.dll"))
        self.dll.xilinx_ip_xfft_v9_1_create_state.argtypes=[Generics]
        self.dll.xilinx_ip_xfft_v9_1_create_state.restype=C.c_void_p
        self.dll.xilinx_ip_xfft_v9_1_destroy_state.argtypes=[C.c_void_p]
        self.dll.xilinx_ip_xfft_v9_1_destroy_state.restype=None
        self.dll.xilinx_ip_xfft_v9_1_bitacc_simulate.argtypes=[C.c_void_p,Inputs,C.POINTER(Outputs)]
        self.dll.xilinx_ip_xfft_v9_1_bitacc_simulate.restype=C.c_int
        self.generics=Generics(maximum,3,int(runtime),0,16,16,1,0,1)
        self.state=self.dll.xilinx_ip_xfft_v9_1_create_state(self.generics)
        if not self.state: raise RuntimeError("Official FFT create_state failed")
    def transform(self, codes, forward, schedule=None):
        codes=np.asarray(codes)
        assert codes.ndim==2 and codes.shape[1]==2
        n=len(codes);nfft=n.bit_length()-1
        assert n==(1<<nfft) and np.all(codes==np.rint(codes))
        assert codes.min()>=-32768 and codes.max()<=32767
        if schedule is None: schedule=[3]+[2]*((nfft+1)//2-2)+([1] if nfft%2 else [2])
        assert len(schedule)==(nfft+1)//2
        re=np.ascontiguousarray(codes[:,0],dtype=np.float64)/32768
        im=np.ascontiguousarray(codes[:,1],dtype=np.float64)/32768
        ore=np.empty(n,dtype=np.float64);oim=np.empty(n,dtype=np.float64)
        sc=np.ascontiguousarray(schedule,dtype=np.int32)
        inp=Inputs(nfft,re.ctypes.data_as(DP),n,im.ctypes.data_as(DP),n,sc.ctypes.data_as(IP),len(sc),int(forward))
        out=Outputs(ore.ctypes.data_as(DP),n,oim.ctypes.data_as(DP),n,0,0)
        rc=self.dll.xilinx_ip_xfft_v9_1_bitacc_simulate(self.state,inp,C.byref(out))
        if rc or out.xk_re_size!=n or out.xk_im_size!=n: raise RuntimeError(f"FFT ABI/result error {rc}")
        raw=np.column_stack((ore,oim))*32768
        assert np.isfinite(raw).all() and np.max(np.abs(raw-np.rint(raw)))==0
        result=np.rint(raw).astype(np.int64)
        assert result.min()>=-32768 and result.max()<=32767
        return result,int(out.overflow)
    def close(self):
        if self.state:
            self.dll.xilinx_ip_xfft_v9_1_destroy_state(self.state)
            self.state=None
        self.dll_dir.close()