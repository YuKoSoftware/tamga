#version 450

// Inputs from vertex shader
layout(location = 0) in vec3 worldPos;
layout(location = 1) in vec3 worldNormal;
layout(location = 2) in vec2 fragUV;
layout(location = 3) in vec4 fragColor;

// Set 0, Binding 0 — camera UBO, per-frame (for viewPos)
layout(set = 0, binding = 0) uniform CameraUBO {
    mat4 view;
    mat4 proj;
    vec3 viewPos;
} camera;

// Set 0, Binding 1 — lights SSBO, per-frame
// Unified light struct: type field distinguishes directional/point/spot.
const uint LIGHT_DIRECTIONAL = 0;
const uint LIGHT_POINT       = 1;
const uint LIGHT_SPOT         = 2;

struct LightData {
    vec4 position_range;  // xyz = position, w = range
    vec4 direction_type;  // xyz = direction, w = float(type)
    vec4 color;           // rgb = color, w unused
    vec4 attenuation;     // x = constant, y = linear, z = quadratic, w unused
    vec4 spot_params;     // x = cos(inner), y = cos(outer), z/w unused
};

layout(std430, set = 0, binding = 1) readonly buffer LightSSBO {
    int  numLights;
    int  _pad1;
    int  _pad2;
    int  _pad3;
    LightData lights[];
} lightSSBO;

// Set 1, Binding 0 — material UBO, per-material
layout(set = 1, binding = 0) uniform MaterialUBO {
    vec4  diffuseColor;
    float specular;
    float shininess;
} material;

// Set 1, Binding 1 — diffuse texture, per-material
layout(set = 1, binding = 1) uniform sampler2D diffuseTexture;

// Output
layout(location = 0) out vec4 outColor;

// Blinn-Phong lighting for all light types

vec3 calcLight(LightData light, vec3 normal, vec3 fragPos, vec3 viewDir, vec4 diffuseColor) {
    uint lightType = uint(light.direction_type.w);

    vec3  lightDir;
    float atten = 1.0;

    if (lightType == LIGHT_DIRECTIONAL) {
        lightDir = normalize(-light.direction_type.xyz);
    } else {
        // Point or spot
        vec3  toLight = light.position_range.xyz - fragPos;
        float dist    = length(toLight);
        lightDir = toLight / dist;
        atten = 1.0 / (light.attenuation.x
                      + light.attenuation.y * dist
                      + light.attenuation.z * dist * dist);

        if (lightType == LIGHT_SPOT) {
            float theta  = dot(lightDir, normalize(-light.direction_type.xyz));
            float inner  = light.spot_params.x;
            float outer  = light.spot_params.y;
            atten *= smoothstep(outer, inner, theta);
        }
    }

    // Ambient
    vec3 ambient = 0.1 * light.color.rgb * diffuseColor.rgb;

    // Diffuse
    float diff    = max(dot(normal, lightDir), 0.0);
    vec3  diffuse = diff * light.color.rgb * diffuseColor.rgb;

    // Specular (Blinn-Phong: half-vector instead of reflect)
    vec3  halfDir = normalize(lightDir + viewDir);
    float spec    = pow(max(dot(normal, halfDir), 0.0), material.shininess);
    vec3  specular = spec * material.specular * light.color.rgb;

    return (ambient + diffuse + specular) * atten;
}

void main() {
    vec3 normal  = normalize(worldNormal);
    vec3 viewDir = normalize(camera.viewPos - worldPos);

    // Sample diffuse texture and combine with vertex color and material color
    vec4 texColor     = texture(diffuseTexture, fragUV);
    vec4 diffuseColor = material.diffuseColor * fragColor * texColor;

    vec3 result = vec3(0.0);

    for (int i = 0; i < lightSSBO.numLights; i++) {
        result += calcLight(lightSSBO.lights[i], normal, worldPos, viewDir, diffuseColor);
    }

    // Fallback ambient when no lights active
    if (lightSSBO.numLights == 0) {
        result = diffuseColor.rgb;
    }

    outColor = vec4(result, diffuseColor.a);
}
