Shader "Custom/Ocean"{
    Properties {
        TessellationEdgeLength ("Tessellation Edge Length", Range(1, 100)) = 100

        Gloss ("Gloss", Range(0,1)) = 1
        Roughness ("Roughness", Range(0, 1)) = 1
        
        ScatterColor ("Scatter Color", Color) = (1, 1, 1, 1)    //AA8F43
        BubblesColor ("Bubbles Color", Color) = (1, 1, 1, 1)    //003AFF
        BubblesDensity ("Bubble Density", Range(0, 10)) = 1
        k1 ("k1", Range(0, 1)) = 1
        k2 ("k2", Range(0, 1)) = 1
        k3 ("k3", Range(0, 1)) = 1
        k4 ("k4", Range(0, 1)) = 1

        [NoScaleOffset] _Skybox ("Skybox", 2D) = "black" {}
        _SkyboxReflectionIntensity ("Skybox Reflection Intensity", Range(0,1)) = 1

        FoamFactor ("Foam Factor", Range(0, 1)) = 1

        // Amplitude (A) should be more accurate when they all sum to one
        A0 ("A0", Range(0, 1)) = 1 
        A1 ("A1", Range(0, 1)) = 0.7 
        A2 ("A2", Range(0, 1)) = 1 

        Displacement0  ("Displacement0", 2D)  = "black" {}
        [NoScaleOffset] Slope0  ("Slope0", 2D)  = "black" {}
        [NoScaleOffset] Foam0 ("Foam0", 2D) = "black" {}

        Displacement1  ("Displacement1", 2D)  = "black" {}
        [NoScaleOffset] Slope1  ("Slope1", 2D)  = "black" {}
        [NoScaleOffset] Foam1 ("Foam1", 2D) = "black" {}
        
        Displacement2  ("Displacement2", 2D)  = "black" {}
        [NoScaleOffset] Slope2  ("Slope2", 2D)  = "black" {}
        [NoScaleOffset] Foam2 ("Foam2", 2D) = "black" {}
    }
    SubShader {
        Tags { 
            "RenderType"="Opaque"
            "Queue"="Geometry"
        }

        Pass {
            Tags {
                "LightMode"="ForwardBase"
            }

            Cull Off

            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_fwdbase
            #pragma multi_compile_fog

            #pragma vertex Vertex
            #pragma hull Hull
            #pragma domain Domain addshadow
            #pragma fragment Fragment

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            #include "SkySampling.cginc"
            
            float TessellationEdgeLength;
            float A;
            #include "Tessellation.cginc"


            float Gloss;
            float Roughness;

            float4 ScatterColor;
            float BubblesDensity;
            float4 BubblesColor;
            float k1;
            float k2;
            float k3;
            float k4;

            sampler2D _Skybox;
            float _SkyboxReflectionIntensity;

            float FoamFactor;


            float L0;
            float L1;
            float L2;

            float A0;
            float A1;
            float A2;

            sampler2D Displacement0;
            float4 Displacement0_ST;
            sampler2D Slope0;
            sampler2D Foam0;

            sampler2D Displacement1;
            float4 Displacement1_ST;
            sampler2D Slope1;
            sampler2D Foam1;

            sampler2D Displacement2;
            float4 Displacement2_ST;
            sampler2D Slope2;
            sampler2D Foam2;


            struct Interpolators {
                float4 pos : SV_POSITION;
                float3 wPos : TEXCOORD0;
                float2 uv : TEXCOORD1;
                LIGHTING_COORDS(2,3)
                UNITY_FOG_COORDS(4)
            };


            [domain("tri")]
            Interpolators Domain(TessellationFactors factors,
	            OutputPatch<TessellationControlPoint, 3> patch,
	            float3 barycentricCoordinates : SV_DomainLocation
            ) {
                Interpolators v;

                UNITY_SETUP_INSTANCE_ID(patch[0]);
	            UNITY_TRANSFER_INSTANCE_ID(patch[0], v);
	            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(v);


                float2 uv = BARYCENTRIC_INTERPOLATE(uv); 
                float3 positionOS = BARYCENTRIC_INTERPOLATE(positionOS);
                float3 positionWS = BARYCENTRIC_INTERPOLATE(positionWS);
                

                float4 texSamp0 = float4(TRANSFORM_TEX(uv, Displacement0), 0, 0);
                float4 texSamp1 = float4(TRANSFORM_TEX(uv, Displacement1), 0, 0);
                float4 texSamp2 = float4(TRANSFORM_TEX(uv, Displacement2), 0, 0);
                
                float3 disp = (A0 * tex2Dlod(Displacement0, texSamp0).xyz) + (A1 * L0/L1 * tex2Dlod(Displacement1, texSamp1).xyz) + (A2 * L0/L2 * tex2Dlod(Displacement2, texSamp2).xyz);
                positionOS.x += 0.01 * disp.x;
                positionOS.y += A * disp.y;
                positionOS.z += 0.01 * disp.z;


                v.pos = UnityObjectToClipPos(float4(positionOS, 1.0));
                v.uv = uv;
                v.wPos = positionWS;

                UNITY_TRANSFER_FOG(v,v.pos);
                TRANSFER_VERTEX_TO_FRAGMENT(v);
                return v;
            }



            #define PI 3.14159265359

            // GGX/Trowbridge-Reitz Normal Distribution
            float D(float alpha, float3 N, float3 H) {
                float numerator = pow(alpha, 2);

                float NdotH = DotClamped(N, H);
                float denominator = PI * pow(pow(NdotH, 2) * (pow(alpha, 2) - 1) + 1, 2);
                denominator = max(denominator, 0.000001);

                return numerator / denominator;
            }
            
            // Schlick-Beckmann Geometry Shadowing
            float G1(float alpha, float3 N, float3 X) {
                float numerator = DotClamped(N, X);

                float k = alpha / 2;
                float denominator = DotClamped(N, X) * (1 - k) + k;
                denominator = max(denominator, 0.000001);
                
                return numerator / denominator;
            }

            // Smith Model
            float G(float alpha, float3 N, float3 V, float3 L) {
                return G1(alpha, N, V) * G1(alpha, N, L);
            }

            // Fresnel-Schlick
            float3 F(float3 F0, float3 V, float3 H) {
                return F0 + (1 - F0) * pow(1 - DotClamped(V, H), 5.0); 
            }


            float4 Fragment(Interpolators i) : SV_Target {
                // SETUP
                // UV coordinates
                float2 uv0 = TRANSFORM_TEX(i.uv, Displacement0);
                float2 uv1 = TRANSFORM_TEX(i.uv, Displacement1);
                float2 uv2 = TRANSFORM_TEX(i.uv, Displacement2);

                // Slope
                float2 dYdx_dYdz = (A0 * tex2D(Slope0, uv0).xy) + (A1 * L0/L1 * tex2D(Slope1, uv1).xy) + (A2 * L0/L2 * tex2D(Slope2, uv2).xy);


                // VECTORS
                // L
                float3 L = UnityWorldSpaceLightDir(i.wPos).xyz;
                float attenuation = LIGHT_ATTENUATION(i);

                // V
                float3 V = normalize(_WorldSpaceCameraPos - i.wPos);
                
                // H
                float3 H = normalize(L + V);

                // N
                float3 tangent = float3(1, dYdx_dYdz.x, 0);
                float3 bitangent = float3(0, dYdx_dYdz.y, 1);
                float3 N = normalize(cross(bitangent, tangent));


                // COLOR INIT
                float3 col = 0;


                // PBR
                float3 F0 = 0;
                float3 Ks = F(F0, V, H);
                float3 Kd = 1 - Ks;

                //Diffuse
                //float3 lambert = (float3(1, 1, 1) / PI) * DotClamped(L, N);
                //col += Kd * lambert;
                
                //Specular
                float3 cookTorranceNumerator = D(Roughness, N, H) * G(Roughness, N, V, L) * Ks;
                float cookTorranceDenominator = 4 * DotClamped(V, N);
                cookTorranceDenominator = max(cookTorranceDenominator, 0.000001);
                float3 cookTorrance = cookTorranceNumerator / cookTorranceDenominator;
                col += 0.05 * cookTorrance; //had to decrease it because it was too strong
                
                //Light properties
                col *= _LightColor0.xyz * attenuation;


                // BLINN-PHONG
                //Diffuse
                //col += DotClamped(N, L) * 0.5;
                
                //Specular
                /*float3 R = reflect(-L, N);
                float specularExponent = exp2(Gloss * 11) + 2;
                float fresnel = pow(1-saturate(DotClamped(V,N)), 5);
                col += pow(saturate(dot(R, V)), specularExponent) * Gloss * fresnel;
                
                //Light properties
                col *= _LightColor0.xyz * attenuation;*/ 


                // SCATTER
                float height = (A0 * tex2D(Displacement0, uv0).y) + (A1 * L0/L1 * tex2D(Displacement1, uv1).y) + (A2 * L0/L2 * tex2D(Displacement2, uv2).y);
                height = max(0, A * height);
                float3 scatter = (k1*height*pow(DotClamped(L, -V), 4) * pow(0.5 - 0.5*dot(L, N), 3)
                                + k2*pow(DotClamped(V, N), 2)) * ScatterColor.xyz;
                scatter        += k3*DotClamped(L, N) * ScatterColor.xyz
                                + k4* BubblesDensity * BubblesColor.xyz;
                col += scatter * _LightColor0.xyz;
                
                
                // IBL REFLECTIONS
                float4x4 yRot = Rotate(90);
                float3 viewRefl_rot = mul(yRot, float4(reflect(-V, N), 1)).xyz;
                col += tex2D(_Skybox, DirToRectilinear(viewRefl_rot)).xyz * _SkyboxReflectionIntensity;
                float mip = (1-Gloss)*6;
                col += tex2Dlod(_Skybox, float4(DirToRectilinear(viewRefl_rot), mip, mip)).xyz * _SkyboxReflectionIntensity;
                
                
                // FOAM
                float foam = (A0 * tex2Dlod(Foam0, float4(uv0, 1, 1)).xyz) + (A1*L1/L0 * tex2Dlod(Foam1, float4(uv1, 1, 1)).xyz) + (A2*L2/L0 * tex2Dlod(Foam2, float4(uv2, 1, 1)).xyz);
                col += FoamFactor * foam * (BubblesColor.xyz + _LightColor0.xyz)/2;



                UNITY_APPLY_FOG(i.fogCoord, col);
                return float4(col, 1);
            }
            ENDCG
        }


        Pass {
            Tags {
                "LightMode"="ShadowCaster"
            }

            CGPROGRAM
            #pragma target 5.0
            #pragma multi_compile_shadowcaster

            #pragma vertex Vertex
            #pragma hull Hull
            #pragma domain Domain
            #pragma fragment Fragment

            #include "UnityCG.cginc"
            #include "Lighting.cginc"
            #include "AutoLight.cginc"

            float TessellationEdgeLength;
            float A;
            #include "Tessellation.cginc"


            float L0;
            float L1;
            float L2;

            float A0;
            float A1;
            float A2;

            sampler2D Displacement0;
            float4 Displacement0_ST;

            sampler2D Displacement1;
            float4 Displacement1_ST;

            sampler2D Displacement2;
            float4 Displacement2_ST;


            struct Interpolators {
                float4 pos : SV_POSITION;
                float3 vec : TEXCOORD0;
            };


            [domain("tri")]
            Interpolators Domain(
	            TessellationFactors factors,
	            OutputPatch<TessellationControlPoint, 3> patch,
	            float3 barycentricCoordinates : SV_DomainLocation
            ){
                Interpolators v;

                UNITY_SETUP_INSTANCE_ID(patch[0]);
	            UNITY_TRANSFER_INSTANCE_ID(patch[0], v);
	            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(v);


                float4 positionOS = float4(BARYCENTRIC_INTERPOLATE(positionOS), 1);
                float2 uv = BARYCENTRIC_INTERPOLATE(uv); 
                

                float4 texSamp0 = float4(TRANSFORM_TEX(uv, Displacement0), 0, 0);
                float4 texSamp1 = float4(TRANSFORM_TEX(uv, Displacement1), 0, 0);
                float4 texSamp2 = float4(TRANSFORM_TEX(uv, Displacement2), 0, 0);

                float3 disp = (A0 * tex2Dlod(Displacement0, texSamp0).xyz) + (A1 * L0/L1 * tex2Dlod(Displacement1, texSamp1).xyz) + (A2 * L0/L2 * tex2Dlod(Displacement2, texSamp2).xyz);
                positionOS.x += 0.01 * disp.x;
                positionOS.y += A * disp.y;
                positionOS.z += 0.01 * disp.z;
                float3 positionWS = mul(UNITY_MATRIX_M, positionOS).xyz;


                v.pos = UnityObjectToClipPos(positionOS);
                float4 opos = UnityClipSpaceShadowCasterPos(positionOS, positionWS);
                v.vec = UnityApplyLinearShadowBias(opos);
	            return v;
            }

            float4 Fragment(Interpolators i) : SV_Target {
                return UnityEncodeCubeShadowDepth ((length(i.vec) + unity_LightShadowBias.x) * _LightPositionRange.w);
            }
            ENDCG
        }
    }
}
