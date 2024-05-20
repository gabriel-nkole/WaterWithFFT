struct MeshData {
	float4 vertex : POSITION;
	float2 uv : TEXCOORD0;
	float4 normalOS : NORMAL;
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct TessellationControlPoint {
	float3 positionOS : TEXCOORD0;
	float3 positionWS : INTERNALTESSPOS;
	float3 normalWS : NORMAL;
	float2 uv : TEXCOORD1;
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

TessellationControlPoint Vertex(MeshData v){
	TessellationControlPoint output;

	UNITY_SETUP_INSTANCE_ID(v);
	UNITY_TRANSFER_INSTANCE_ID(v, output);

	output.positionOS = v.vertex.xyz;
	output.positionWS = mul(UNITY_MATRIX_M, v.vertex).xyz;
    output.normalWS = UnityObjectToWorldNormal(v.normalOS.xyz);
	
	output.uv = v.uv;
	return output;
}




[domain("tri")]
[outputcontrolpoints(3)]
[outputtopology("triangle_cw")]
[patchconstantfunc("PatchConstantFunction")]
[partitioning("fractional_even")]
TessellationControlPoint Hull(
	InputPatch<TessellationControlPoint, 3> patch,
	uint id : SV_OutputControlPointID
){
	return patch[id];		
}


struct TessellationFactors {
	float edge[3] : SV_TessFactor;
	float inside : SV_InsideTessFactor;
};

bool TriangleIsBelowClipPlane (
	float3 p0, float3 p1, float3 p2, int planeIndex, float bias
){
	float4 plane = unity_CameraWorldClipPlanes[planeIndex];
	return
		dot(float4(p0, 1), plane) < bias &&
		dot(float4(p1, 1), plane) < bias &&
		dot(float4(p2, 1), plane) < bias;
}
bool TriangleIsCulled (float3 p0, float3 p1, float3 p2, float bias){
	return TriangleIsBelowClipPlane(p0, p1, p2, 0, bias) ||
		   TriangleIsBelowClipPlane(p0, p1, p2, 1, bias) ||
		   TriangleIsBelowClipPlane(p0, p1, p2, 2, bias) ||
		   TriangleIsBelowClipPlane(p0, p1, p2, 3, bias);
}

float TessellationEdgeFactor (
	float3 p0, float3 p1
) {
	float edgeLength = distance(p0, p1);

	float3 edgeCenter = (p0 + p1) * 0.5;
	float viewDistance = distance(edgeCenter, _WorldSpaceCameraPos);

	return edgeLength * _ScreenParams.y / (TessellationEdgeLength * viewDistance);
}


TessellationFactors PatchConstantFunction(
	InputPatch<TessellationControlPoint, 3> patch)
{
	UNITY_SETUP_INSTANCE_ID(patch[0]);
	TessellationFactors f;

	float bias = -4 * A;
	float3 p0 = patch[0].positionWS;
	float3 p1 = patch[1].positionWS;
	float3 p2 = patch[2].positionWS;

	if (TriangleIsCulled(p0, p1, p2, bias)){
		f.edge[0] = f.edge[1] = f.edge[2] = f.inside = 0;
	}
	
	else{
		f.edge[0] = TessellationEdgeFactor(p1, p2);
		f.edge[1] = TessellationEdgeFactor(p2, p0);
		f.edge[2] = TessellationEdgeFactor(p0, p1);
		f.inside = 
			(TessellationEdgeFactor(p1, p2) +
			 TessellationEdgeFactor(p2, p0) +
			 TessellationEdgeFactor(p0, p1)) * (1 / 3.0);
	}

	return f;
}

#define BARYCENTRIC_INTERPOLATE(fieldName) \
		patch[0].fieldName * barycentricCoordinates.x + \
		patch[1].fieldName * barycentricCoordinates.y + \
		patch[2].fieldName * barycentricCoordinates.z


