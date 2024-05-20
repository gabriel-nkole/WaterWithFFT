#define TAU 6.28318530718
#define PI 3.14159265359
#define Deg2Rad PI/180

float2 DirToRectilinear(float3 dir){
    float x = (atan2(dir.z, dir.x)) / TAU + 0.5; //0-1
    float y = (dir.y * 0.5 + 0.5); //0-1
    return float2(x, y);
}

float4x4 Rotate(float yDeg){
    float yRad = Deg2Rad * yDeg;

    return float4x4( cos(yRad), 0, sin(yRad),       0,
                        0,         1,         0,       0,
                    -sin(yRad), 0, cos(yRad),       0,
                        0,         0,         0,       1);
}