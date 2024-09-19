Shader "Custom/WaterSky" {
    Properties {
        [NoScaleOffset] _MainTex ("Rectlinear Texture", 2D) = "white" {}
    }
    SubShader {
        Tags { "RenderType"="Opaque" }

        Pass {
            CGPROGRAM
            #pragma vertex Vertex
            #pragma fragment Fragment

            #include "UnityCG.cginc"

            #include "SkySampling.cginc"


            struct MeshData {
                float4 vertex : POSITION;
                float3 viewDir : TEXCOORD0;
            };

            struct Interpolators {
                float3 viewDir : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;


            Interpolators Vertex(MeshData v) {
                Interpolators o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.viewDir = v.viewDir;
                return o;
            }

            float3 Fragment(Interpolators i) : SV_Target {
                // sample the texture
                float3 rotatedViewDir = mul(Rotate(90), float4(i.viewDir, 1)).xyz;
                float3 col = tex2D(_MainTex, DirToRectilinear(rotatedViewDir));
                return col;
            }
            ENDCG
        }
    }
}
