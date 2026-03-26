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

// Set 0, Binding 1 — lights UBO, per-frame
struct DirLight {
    vec4 direction; // w unused
    vec4 color;     // w unused
};

struct PointLight {
    vec4 position;  // w unused
    vec4 color;     // w unused
    float constant;
    float linear;
    float quadratic;
    float _pad;
};

layout(set = 0, binding = 1) uniform LightUBO {
    DirLight   dirLights[4];
    PointLight pointLights[8];
    int        numDirLights;
    int        numPointLights;
} lights;

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

// Phong lighting helpers

vec3 calcDirLight(DirLight light, vec3 normal, vec3 viewDir, vec4 diffuseColor) {
    vec3 lightDir = normalize(-light.direction.xyz);

    // Ambient
    vec3 ambient = 0.1 * light.color.rgb * diffuseColor.rgb;

    // Diffuse
    float diff    = max(dot(normal, lightDir), 0.0);
    vec3  diffuse = diff * light.color.rgb * diffuseColor.rgb;

    // Specular
    vec3  reflectDir = reflect(-lightDir, normal);
    float spec       = pow(max(dot(viewDir, reflectDir), 0.0), material.shininess);
    vec3  specular   = spec * material.specular * light.color.rgb;

    return ambient + diffuse + specular;
}

vec3 calcPointLight(PointLight light, vec3 normal, vec3 fragPos, vec3 viewDir, vec4 diffuseColor) {
    vec3  lightDir = normalize(light.position.xyz - fragPos);
    float dist     = length(light.position.xyz - fragPos);
    float atten    = 1.0 / (light.constant + light.linear * dist + light.quadratic * dist * dist);

    // Ambient
    vec3 ambient = 0.1 * light.color.rgb * diffuseColor.rgb;

    // Diffuse
    float diff    = max(dot(normal, lightDir), 0.0);
    vec3  diffuse = diff * light.color.rgb * diffuseColor.rgb;

    // Specular
    vec3  reflectDir = reflect(-lightDir, normal);
    float spec       = pow(max(dot(viewDir, reflectDir), 0.0), material.shininess);
    vec3  specular   = spec * material.specular * light.color.rgb;

    return (ambient + diffuse + specular) * atten;
}

void main() {
    vec3 normal  = normalize(worldNormal);
    vec3 viewDir = normalize(camera.viewPos - worldPos);

    // Sample diffuse texture and combine with vertex color and material color
    vec4 texColor    = texture(diffuseTexture, fragUV);
    vec4 diffuseColor = material.diffuseColor * fragColor * texColor;

    vec3 result = vec3(0.0);

    // Accumulate directional lights
    for (int i = 0; i < lights.numDirLights; i++) {
        result += calcDirLight(lights.dirLights[i], normal, viewDir, diffuseColor);
    }

    // Accumulate point lights
    for (int i = 0; i < lights.numPointLights; i++) {
        result += calcPointLight(lights.pointLights[i], normal, worldPos, viewDir, diffuseColor);
    }

    // Fallback ambient when no lights active
    if (lights.numDirLights == 0 && lights.numPointLights == 0) {
        result = diffuseColor.rgb;
    }

    outColor = vec4(result, diffuseColor.a);
}
