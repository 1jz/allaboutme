#version 300 es

#ifdef GL_ES
precision mediump float;
#endif

// Adapted from FastNoiseLite

// Switch between using floats or doubles for input position
#define FNLfloat float
//#define FNLfloat double

// Utilities
int _fnlFastFloor(FNLfloat f) { return int(floor(f)); }
float _fnlInterpQuintic(float t) { return t * t * t * (t * (t * 6.f - 15.f) + 10.f); }
float _fnlLerp(float a, float b, float t) { return mix(a, b, t); }


// From here on, this is private implementation
// Constants
const float GRADIENTS_3D[] =float[]
(
    0.f, 1.f, 1.f, 0.f,  0.f,-1.f, 1.f, 0.f,  0.f, 1.f,-1.f, 0.f,  0.f,-1.f,-1.f, 0.f,
    1.f, 0.f, 1.f, 0.f, -1.f, 0.f, 1.f, 0.f,  1.f, 0.f,-1.f, 0.f, -1.f, 0.f,-1.f, 0.f,
    1.f, 1.f, 0.f, 0.f, -1.f, 1.f, 0.f, 0.f,  1.f,-1.f, 0.f, 0.f, -1.f,-1.f, 0.f, 0.f,
    0.f, 1.f, 1.f, 0.f,  0.f,-1.f, 1.f, 0.f,  0.f, 1.f,-1.f, 0.f,  0.f,-1.f,-1.f, 0.f,
    1.f, 0.f, 1.f, 0.f, -1.f, 0.f, 1.f, 0.f,  1.f, 0.f,-1.f, 0.f, -1.f, 0.f,-1.f, 0.f,
    1.f, 1.f, 0.f, 0.f, -1.f, 1.f, 0.f, 0.f,  1.f,-1.f, 0.f, 0.f, -1.f,-1.f, 0.f, 0.f,
    0.f, 1.f, 1.f, 0.f,  0.f,-1.f, 1.f, 0.f,  0.f, 1.f,-1.f, 0.f,  0.f,-1.f,-1.f, 0.f,
    1.f, 0.f, 1.f, 0.f, -1.f, 0.f, 1.f, 0.f,  1.f, 0.f,-1.f, 0.f, -1.f, 0.f,-1.f, 0.f,
    1.f, 1.f, 0.f, 0.f, -1.f, 1.f, 0.f, 0.f,  1.f,-1.f, 0.f, 0.f, -1.f,-1.f, 0.f, 0.f,
    0.f, 1.f, 1.f, 0.f,  0.f,-1.f, 1.f, 0.f,  0.f, 1.f,-1.f, 0.f,  0.f,-1.f,-1.f, 0.f,
    1.f, 0.f, 1.f, 0.f, -1.f, 0.f, 1.f, 0.f,  1.f, 0.f,-1.f, 0.f, -1.f, 0.f,-1.f, 0.f,
    1.f, 1.f, 0.f, 0.f, -1.f, 1.f, 0.f, 0.f,  1.f,-1.f, 0.f, 0.f, -1.f,-1.f, 0.f, 0.f,
    0.f, 1.f, 1.f, 0.f,  0.f,-1.f, 1.f, 0.f,  0.f, 1.f,-1.f, 0.f,  0.f,-1.f,-1.f, 0.f,
    1.f, 0.f, 1.f, 0.f, -1.f, 0.f, 1.f, 0.f,  1.f, 0.f,-1.f, 0.f, -1.f, 0.f,-1.f, 0.f,
    1.f, 1.f, 0.f, 0.f, -1.f, 1.f, 0.f, 0.f,  1.f,-1.f, 0.f, 0.f, -1.f,-1.f, 0.f, 0.f,
    1.f, 1.f, 0.f, 0.f,  0.f,-1.f, 1.f, 0.f, -1.f, 1.f, 0.f, 0.f,  0.f,-1.f,-1.f, 0.f
);

// Hashing
const int PRIME_X = 501125321;
const int PRIME_Y = 1136930381;
const int PRIME_Z = 1720413743;

int _fnlHash3D(int seed, int xPrimed, int yPrimed, int zPrimed)
{
    int hash = seed ^ xPrimed ^ yPrimed ^ zPrimed;

    hash *= 0x27d4eb2d;
    return hash;
}

struct fnl_state
{
    // Seed used for noise.
    // @remark Default: 1337
    int seed;
    
    // The frequency for noise.
    // @remark Default: 0.01
    float frequency;
    
    // The maximum warp distance from original position when using DomainWarp.
    // @remark Default: 1.0
    float domain_warp_amp;
};

fnl_state fnlCreateState(int seed)
{
    fnl_state newState;
    newState.seed = seed;
    newState.frequency = 0.01f;
    newState.domain_warp_amp = 1.0f;
    
    return newState;
}

float _fnlGradCoord3D(int seed, int xPrimed, int yPrimed, int zPrimed, float xd, float yd, float zd)
{
    int hash = _fnlHash3D(seed, xPrimed, yPrimed, zPrimed);
    hash ^= hash >> 15;
    hash &= 63 << 2;
    return xd * GRADIENTS_3D[hash] + yd * GRADIENTS_3D[hash | 1] + zd * GRADIENTS_3D[hash | 2];
}

float _fnlSinglePerlin3D(int seed, FNLfloat x, FNLfloat y, FNLfloat z)
{
    int x0 = _fnlFastFloor(x);
    int y0 = _fnlFastFloor(y);
    int z0 = _fnlFastFloor(z);

    float xd0 = x - float(x0);
    float yd0 = y - float(y0);
    float zd0 = z - float(z0);
    float xd1 = xd0 - 1.f;
    float yd1 = yd0 - 1.f;
    float zd1 = zd0 - 1.f;

    float xs = _fnlInterpQuintic(xd0);
    float ys = _fnlInterpQuintic(yd0);
    float zs = _fnlInterpQuintic(zd0);

    x0 *= PRIME_X;
    y0 *= PRIME_Y;
    z0 *= PRIME_Z;
    int x1 = x0 + PRIME_X;
    int y1 = y0 + PRIME_Y;
    int z1 = z0 + PRIME_Z;

    float xf00 = _fnlLerp(_fnlGradCoord3D(seed, x0, y0, z0, xd0, yd0, zd0), _fnlGradCoord3D(seed, x1, y0, z0, xd1, yd0, zd0), xs);
    float xf10 = _fnlLerp(_fnlGradCoord3D(seed, x0, y1, z0, xd0, yd1, zd0), _fnlGradCoord3D(seed, x1, y1, z0, xd1, yd1, zd0), xs);
    float xf01 = _fnlLerp(_fnlGradCoord3D(seed, x0, y0, z1, xd0, yd0, zd1), _fnlGradCoord3D(seed, x1, y0, z1, xd1, yd0, zd1), xs);
    float xf11 = _fnlLerp(_fnlGradCoord3D(seed, x0, y1, z1, xd0, yd1, zd1), _fnlGradCoord3D(seed, x1, y1, z1, xd1, yd1, zd1), xs);

    float yf0 = _fnlLerp(xf00, xf10, ys);
    float yf1 = _fnlLerp(xf01, xf11, ys);

    return _fnlLerp(yf0, yf1, zs) * 0.964921414852142333984375;
}

float fnlGetNoise3D(fnl_state state, FNLfloat x, FNLfloat y, FNLfloat z)
{
    x *= state.frequency;
    y *= state.frequency;
    z *= state.frequency;
    return _fnlSinglePerlin3D(state.seed, x, y, z);
}

uniform float u_time;
out vec4 fragColor;
void main()
{
    fnl_state state = fnlCreateState(1337);
	state.frequency = .005f;
    state.domain_warp_amp = 119.0;

    float x = gl_FragCoord.x + u_time * 30.0;
    float y = 50.f + u_time * 5.0;
    float z = gl_FragCoord.y + u_time * 10.0;

    float noise = fnlGetNoise3D(state, x, y, z) / 2.f + 0.5f;

    // Posterize
    float levels = 10.0;
    float rounding_threshold = 0.0015;

    float rounded = floor(noise * levels) / levels;
    float rounding_error = abs(rounded - noise) / 2.0;

    //vec3 lines = vec3(1.0,0.80,1.0);
    //vec3 bg = vec3(0.65,0.30,1.0);
    //vec3 lines = vec3(1.0,1.0,1.0);
    //vec3 bg = vec3(0.,0.,0.);
    vec3 lines = vec3(0.69, 0.9, 0.69);
    vec3 bg = vec3(0.08, 0.43, 0.31);

    if (rounding_error < rounding_threshold) {
        fragColor = vec4(lines, 1.0);
    } else {
        fragColor = vec4(bg, 1.0);
    }
}