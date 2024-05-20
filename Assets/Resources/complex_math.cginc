float2 complex_add(float2 n1, float2 n2){
    float2 result;
    result.x = n1.x + n2.x;
    result.y = n1.y + n2.y;

    return result;
}

float2 complex_mul(float2 n1, float2 n2){
    float2 result;
    result.x = n1.x*n2.x - n1.y*n2.y;
    result.y = n1.x*n2.y + n1.y*n2.x;

    return result;
}

float2 complex_inv(float2 n){
    float magSq = n.x*n.x + n.y*n.y;
    
    float2 result;
    result.x = n.x/magSq;
    result.y = -n.y/magSq;

    return result;
}