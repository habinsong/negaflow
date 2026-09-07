import CoreImage
import Foundation

// 계수는 Swift 저작값에서 구성합니다. Metal 전용으로 복사한 두 번째 계수표를 두지 않습니다.
enum CustomColorTargetKernel {
    static let kernel: CIColorKernel? = {
        try? CIKernel.kernels(withMetalString: source).first as? CIColorKernel
    }()

    static var source: String {
        func table(_ name: String, _ values: [[Double]]) -> String {
            let rows = values.map { row in
                "{" + row.map { String($0) }.joined(separator: ",") + "}"
            }.joined(separator: ",\n")
            return "constant float \(name)[18][\(values[0].count)] = {\n\(rows)\n};\n"
        }
        let profiles = CustomColorTarget.profiles
        var data = "#include <CoreImage/CoreImage.h>\nusing namespace metal;\n"
        for (name, values) in [
            ("ctTone", profiles.map(\.tone)), ("ctSlope", profiles.map(\.slopes)),
            ("ctGain", profiles.map(\.gain)), ("ctDensity", profiles.map(\.density)),
            ("ctHueShadow", profiles.map(\.hueShadow)), ("ctHueMid", profiles.map(\.hueMid)),
            ("ctHueHigh", profiles.map(\.hueHigh)), ("ctHighlightHue", profiles.map(\.highlightHue)),
            ("ctControls", profiles.map { [$0.controls.x, $0.controls.y, $0.controls.z, $0.controls.w] }),
            ("ctTintShadow", profiles.map { [$0.tintShadow.x, $0.tintShadow.y] }),
            ("ctTintMid", profiles.map { [$0.tintMid.x, $0.tintMid.y] }),
            ("ctTintHigh", profiles.map { [$0.tintHigh.x, $0.tintHigh.y] }),
        ] { data += table(name, values) }
        return data + functions
    }

    private static let functions = """
    constant float ctX[10] = {0,5,10,20,35,50,65,80,90,100};
    inline float ctLabTransfer(float v) {
        return v > 216.0/24389.0 ? pow(v, 1.0/3.0) : ((24389.0/27.0)*v+16.0)/116.0;
    }
    inline float ctLabInverse(float v) {
        float d = 6.0/29.0;
        return v > d ? v*v*v : 3.0*d*d*(v-4.0/29.0);
    }
    inline float3 ctRGBToLab(float3 rgb) {
        float3 d65 = float3(dot(rgb,float3(.4124564,.3575761,.1804375)),
                            dot(rgb,float3(.2126729,.7151522,.072175)),
                            dot(rgb,float3(.0193339,.119192,.9503041)));
        float3 d50 = float3(dot(d65,float3(1.0478112,.0228866,-.0501270)),
                            dot(d65,float3(.0295424,.9904844,-.0170491)),
                            dot(d65,float3(-.0092345,.0150436,.7521316)));
        float3 f = float3(ctLabTransfer(d50.x/.96422), ctLabTransfer(d50.y), ctLabTransfer(d50.z/.82521));
        return float3(116.0*f.y-16.0,500.0*(f.x-f.y),200.0*(f.y-f.z));
    }
    inline float3 ctLabToRGB(float3 lab) {
        float fy = (lab.x+16.0)/116.0;
        float3 d50 = float3(ctLabInverse(fy+lab.y/500.0)*.96422,ctLabInverse(fy),ctLabInverse(fy-lab.z/200.0)*.82521);
        float3 d65 = float3(dot(d50,float3(.9555766,-.0230393,.0631636)),
                            dot(d50,float3(-.0282895,1.0099416,.0210077)),
                            dot(d50,float3(.0122982,-.0204830,1.3299098)));
        return float3(dot(d65,float3(3.2404542,-1.5371385,-.4985314)),
                      dot(d65,float3(-.9692660,1.8760108,.0415560)),
                      dot(d65,float3(.0556434,-.2040259,1.0572252)));
    }
    inline float ctCurve(float l, int p) {
        if (l <= 0.0) return ctTone[p][0]+l*ctSlope[p][0];
        if (l >= 100.0) return ctTone[p][9]+(l-100.0)*ctSlope[p][9];
        int i = 0;
        for (int j=1;j<9;j++) if (l >= ctX[j]) i=j;
        float dx=ctX[i+1]-ctX[i], z=(l-ctX[i])/dx, z2=z*z, z3=z2*z;
        return (2.0*z3-3.0*z2+1.0)*ctTone[p][i]+(z3-2.0*z2+z)*dx*ctSlope[p][i]
             +(-2.0*z3+3.0*z2)*ctTone[p][i+1]+(z3-z2)*dx*ctSlope[p][i+1];
    }
    inline float ctSample(constant float *values, float h) {
        float index=h/45.0; int i=int(floor(index))%8;
        return mix(values[i],values[(i+1)%8],fract(index));
    }
    [[stitchable]] float4 customColorTarget(coreimage::sample_t src, float profileIndex) {
        if (src.a <= 0.0) return float4(0.0);
        float3 rgb=src.rgb/src.a;
        // 비정상 입력으로 계수 배열을 참조하지 않습니다.
        if (!all(isfinite(rgb))) return float4(NAN,NAN,NAN,src.a);
        int p=int(profileIndex);
        float3 lab=ctRGBToLab(rgb);
        float l=lab.x, c=length(lab.yz);
        float h=c==0.0 ? 0.0 : fmod(atan2(lab.z,lab.y)*180.0/M_PI_F+360.0,360.0);
        float k=ctSample(ctDensity[p],h)*c/(c+24.0), t=ctCurve(l,p)/100.0;
        float lout=100.0*(t<0.0 ? t/(1.0+k) : (t>1.0 ? 1.0+(1.0+k)*(t-1.0) : t/(1.0+k*(1.0-t))));
        float4 controls=float4(ctControls[p][0],ctControls[p][1],ctControls[p][2],ctControls[p][3]);
        float wc=smoothstep(2.0,10.0,c);
        float g=1.0+(ctSample(ctGain[p],h)-1.0)*wc;
        float base=c*g*mix(controls.x,1.0,smoothstep(0.0,28.0,l));
        if (base>48.0) { float excess=base-48.0; base=48.0+excess/(1.0+excess/48.0); }
        float drive=mix(l,lout,controls.w), v=max((drive-controls.y)/(100.0-controls.y),0.0);
        float cout=base/(1.0+controls.z*v*v*(1.0+base/80.0));
        float loss=base==0.0 ? 0.0 : clamp((base-cout)/base,0.0,1.0);
        float rotation=l<50.0 ? mix(ctSample(ctHueShadow[p],h),ctSample(ctHueMid[p],h),clamp((l-20.0)/30.0,0.0,1.0))
                              : mix(ctSample(ctHueMid[p],h),ctSample(ctHueHigh[p],h),clamp((l-50.0)/30.0,0.0,1.0));
        float angle=(h+(rotation+ctSample(ctHighlightHue[p],h)*loss)*wc)*M_PI_F/180.0;
        float2 sh=float2(ctTintShadow[p][0],ctTintShadow[p][1]);
        float2 md=float2(ctTintMid[p][0],ctTintMid[p][1]);
        float2 hi=float2(ctTintHigh[p][0],ctTintHigh[p][1]);
        float2 tint=l<20.0 ? sh*clamp(l/20.0,0.0,1.0) : (l<50.0 ? mix(sh,md,(l-20.0)/30.0)
                        : (l<80.0 ? mix(md,hi,(l-50.0)/30.0) : hi*(1.0-clamp((l-80.0)/20.0,0.0,1.0))));
        float2 ab=cout*float2(cos(angle),sin(angle))+tint*(1.0-smoothstep(25.0,75.0,c));
        return float4(ctLabToRGB(float3(lout,ab))*src.a,src.a);
    }
    """
}
