#define MAX_STEP 1100
#define MIN_DIST 0.000001
#define MAX_DIST 100.0
#define REFLECTION_COUNT 3
#define REFRACTION_COUNT 4
//do not use AA if you have slow gpu
//#define AA


const mat2 m = mat2( 0.80,  0.60, -0.60,  0.80 );

float noise( in vec2 p )
{
	return sin(p.x)*sin(p.y);
}

float fbm( vec2 p )
{
    float f = 0.0;
    f += 0.500000*(0.5+0.5*noise( p )); p = m*p*2.02;
    f += 0.250000*(0.5+0.5*noise( p )); p = m*p*2.03;
    f += 0.125000*(0.5+0.5*noise( p )); p = m*p*2.01;
    f += 0.062500*(0.5+0.5*noise( p )); p = m*p*2.04;
    f += 0.031250*(0.5+0.5*noise( p )); p = m*p*2.01;
    f += 0.015625*(0.5+0.5*noise( p ));
    return f/0.96875;
}

vec3 getRayDirection(vec2 pixelCoord, vec3 cameraPos, vec3 lookAt) {
    vec3 ww = normalize(lookAt - cameraPos);
    vec3 uu = normalize(cross(ww, vec3(0,1,0)));
    vec3 vv = normalize(cross(uu, ww));
    
    return pixelCoord.x * uu + pixelCoord.y * vv + ww;
}

float sph(in vec3 pos, in vec3 cen, in float r) {
	return length(pos - cen) - r; 
}

struct intersection {
    vec3 pos;
    float d;
    // 0 - transparent sphere 
    float type;
};


vec2 map(in vec3 ray) {
    
    vec3 firstSph = vec3(0.0, 0.0, 0.0);
    float sphR = 1.5;
    float disp = sin(1.0*ray.x + iTime) * sin(1.0*ray.y + iTime) * sin(1.0*ray.z + iTime * 0.1) * 0.15;
    vec3 secondSph = vec3(1.0, 0.0, 6.30);
    
    
    float d = sph(ray, firstSph, sphR) + disp;
    return vec2(d, 1.0);
}

vec3 normal(in vec3 pos)
{
	const vec3 eps = vec3(0.01, 0.0, 0.0);
        
    float grad_x = map(pos + eps.xyy).x - map(pos - eps.xyy).x;
    float grad_y = map(pos + eps.yxy).x - map(pos - eps.yxy).x;
    float grad_z = map(pos + eps.yyx).x - map(pos - eps.yyx).x;
  
    return normalize(vec3(grad_x, grad_y, grad_z));
}

intersection rayMarching(vec3 ro, vec3 rd, float sgn) {
    
    float t = 0.0; 
    intersection res;
    
    for(int i = 0; i < MAX_STEP; i++){
    
    	vec2 pos = map(ro + t * rd);
        float dist = pos.x * sgn;
        
        if(dist < MIN_DIST){
            
            res.pos = ro + t * rd;
            res.d = t;
            res.type = pos.y;
            return res;
        } 
        
        if(dist > MAX_DIST){
        	break;
        }
        
        t += 0.01;
    }
    res.pos = vec3(-1.0);
    res.d = -1.0;
    res.type = -1.0;
    return res;
}

float pattern( in vec2 p, out vec2 q, out vec2 r )
{
    q.x = fbm( p + vec2(0.0,0.1 * iTime) );
    q.y = fbm( p + vec2(5.2,1.3) );

    r.x = fbm( p + 4.0*q + vec2(100.7 + 0.1 * iTime,91.2) );
    r.y = fbm( p + 4.0*q + vec2(90.3,2.8 + 0.1 * iTime) );

    return fbm(vec2(fbm( p * p + 10.0*r + fbm(5.0 * p + q)), fbm(100.0 * p * p * q)));
}

vec4 reflection(in vec3 ro, in vec3 rd) {
    vec4 col = vec4(0.0);
    
	for (int i = 0; i < REFLECTION_COUNT; i++) {
        
        intersection result = rayMarching(ro, rd, 1.0);
        
        vec3 newRO = ro;
        vec3 newRD = rd;
        
        if (result.type == 1.0) {
            vec3 n = normal(result.pos);
            vec3 p = normalize(ro - rd);
            vec2 q = vec2(1.0);
            vec2 rr = vec2(1.0);
            float r = pattern(p.xy, q, rr);
            float g = pattern(p.yz, q, rr);
            float b = pattern(p.zx, q, rr);
            col =  (texture(iChannel0, rd) + 0.09 * vec4(r, 0.45 * g, b, 1.0)) *  max(0.75, dot(n, p));
            
            
            col *= 2.0 * vec4(r, g, b, 1.0), vec4(0.1);
            
            newRD = reflect(rd, n);
            newRO = result.pos + newRD * 0.1;
            
        }
        
        if (result.type == -1.0) {
            if (i == 0)
                col = texture(iChannel0, rd);
            else 
                col = mix(texture(iChannel0, rd), col, 0.75);
        }
        
        ro = newRO;
        rd = newRD;
        
        
    }
    
    return col;
    
}

vec4 refraction(in vec3 ro, in vec3 rd, in float refractionRatio, float sgn) {
    vec4 col = vec4(0.0);
    
    
	for (int i = 0; i < REFRACTION_COUNT; i++) {
        
        intersection result = rayMarching(ro, rd, sgn);
        vec3 n = sgn * normal(result.pos);
        
        if (i == 0 && result.type != 1.0) {
            break;
        }
        
        if (result.type == 1.0) {
            
        
            col = texture(iChannel0, ro);

        }
        
        vec3 refractDir = refract(rd, n, refractionRatio);
        vec3 reflectDir = reflect(rd, n);


        if (dot(refractDir, refractDir) < 0.001) {
                //total internal reflection
                rd = reflectDir;
                ro = result.pos + rd * 0.01;
        } else {
                //flip normal direction and refractionRatio for the next ray
                rd = refractDir;
                ro = result.pos + rd * 0.01;
                refractionRatio = 1.0 / refractionRatio;
   
        } 
        
        
        
    }
    
    return col;
}


vec4 render(in vec3 ro, in vec3 rd) {

    vec4 reflection = reflection(ro, rd);
    vec4 refractionCol = refraction(ro, rd, 1.0/1.4, 1.0);
    
    vec3 col = reflection.xyz + 0.2 * refractionCol.xyz;
    
	col = pow(col, vec3(1.0/1.2)); 
    
    
    return vec4(col, 1.0);

}



void mainImage(out vec4 fragColor, in vec2 fragCoord )
{
    // Normalized pixel coordinates (from -1 to 1)
    vec2 uv = (2.0 * fragCoord - iResolution.xy) / iResolution.y;
    
    vec3 cameraPos = vec3(1.0, 1.0, 2.5);
    vec3 lookAt = vec3(0.0);
    // simple antialiasing
    vec3 rayDir1 = getRayDirection(uv, cameraPos, lookAt);
    vec4 col = render(cameraPos, rayDir1); 
    fragColor = col;
#ifdef AA
    vec3 rayDir2 = getRayDirection(uv, cameraPos, lookAt + vec3(0.01, 0.0, 0.0));
    vec3 rayDir3 = getRayDirection(uv, cameraPos, lookAt + vec3(0.0, 0.01, 0.0));
    vec3 rayDir4 = getRayDirection(uv, cameraPos, lookAt + vec3(0.0, 0.0, 0.01));
    vec4 col1 = render(cameraPos, rayDir2);
    vec4 col2 = render(cameraPos, rayDir3);
    vec4 col3 = render(cameraPos, rayDir4);
    // Output to screen
    fragColor = 0.25 * (col + col1 + col2 + col3);
#endif
    
}
