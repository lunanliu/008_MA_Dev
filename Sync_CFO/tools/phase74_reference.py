"""Integer reference for the frozen 74-point phase path; no waveform experiments."""
import math
N=74
ATAN=[round(math.atan(2.0**(-i))/(2*math.pi)*(1<<31)) for i in range(24)]
def rne(n,d):
 sign=-1 if n<0 else 1;q,r=divmod(abs(n),d)
 return sign*(q+int(2*r>d or (2*r==d and q%2)))
def phase74(z):
 assert len(z)==74
 angles=[];unwrapped=[];sat=0;offset=0;unwrap_positive=unwrap_negative=0
 for j,(x,y) in enumerate(z):
  assert isinstance(x,int) and isinstance(y,int) and abs(x)<1<<37 and abs(y)<1<<37
  a=0
  if x<0:a=(1 if y>=0 else -1)*(1<<30);x,y=-x,-y
  for i,k in enumerate(ATAN):
   d=-1 if y<0 else 1;xn=x+d*(y>>i);yn=y-d*(x>>i);a+=d*k
   sat+=int(xn<-(1<<39) or xn>=(1<<39))+int(yn<-(1<<39) or yn>=(1<<39))
   x=max(-(1<<39),min((1<<39)-1,xn));y=max(-(1<<39),min((1<<39)-1,yn))
  if j:
   diff=a-angles[-1]
   if diff>1<<30:offset-=1<<31;unwrap_negative+=1
   elif diff<-(1<<30):offset+=1<<31;unwrap_positive+=1
  angles.append(a);unwrapped.append(a+offset)
 weighted=sum((2*j-73)*a for j,a in enumerate(unwrapped));assert abs(weighted)<1<<49
 code=rne(weighted*15625,1239089152);assert abs(code)<1<<31
 predicted=[rne(code*j*458752,390625) for j in range(N)]
 residual=[a-b for a,b in zip(unwrapped,predicted)];total=sum(residual)
 centered=[N*r-total for r in residual];maximum=max(abs(x) for x in centered)
 nonzero=any(x or y for x,y in z)
 return dict(angle_turn_q31=angles,unwrapped_turn_q31=unwrapped,weighted_sum=weighted,phase_q16=code,predicted_turn_q31=predicted,residual_turn_q31=residual,centered_residual_times74=centered,max_centered=maximum,cordic_saturation=sat,nonzero=bool(nonzero),phase_linear=bool(nonzero and sat==0 and 20*maximum<=74*(1<<31)),unwrap_positive=unwrap_positive,unwrap_negative=unwrap_negative,atan_turn_q31=ATAN)
def pack(fields):
 word=0
 for value,bits in fields:word=(word<<bits)|(int(value)&((1<<bits)-1))
 return word

def unit_cases():
 h=(1<<36);maxv=(1<<37)-1
 axes=[(h,0),(h,h),(0,h),(-h,h),(-h,0),(-h,-h),(0,-h),(h,-h)]
 return [
  ('zero_input',[(0,0)]*N),
  ('positive_axis',[(h,0)]*N),
  ('negative_axis',[(-h,0)]*N),
  ('maximum_legal_components',[(maxv,maxv)]*N),
  ('wrap_positive',[axes[i%8] for i in range(N)]),
  ('wrap_negative',[axes[(-i)%8] for i in range(N)]),
  ('half_turn_boundary',[(h if i%2==0 else -h,0) for i in range(N)]),
  ('small_integer_rounding',[(i%7-3,(i*3)%11-5) for i in range(N)])]