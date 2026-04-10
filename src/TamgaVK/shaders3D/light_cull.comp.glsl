#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Push constants: cluster grid configuration
layout(push_constant) uniform ClusterConfig {
    uint tiles_x;
    uint tiles_y;
    uint depth_slices;
    float near_plane;
    float far_plane;
    uint screen_width;
    uint screen_height;
    uint sample_count;
} config;

// Set 0, Binding 0 — camera UBO (shared with graphics passes)
layout(set = 0, binding = 0) uniform CameraUBO {
    mat4 view;
    mat4 proj;
    vec3 viewPos;
} camera;

// Set 0, Binding 1 — lights SSBO (shared with graphics passes)
struct LightData {
    vec4 position_range;  // xyz = position, w = range
    vec4 direction_type;  // xyz = direction, w = type (0=dir, 1=point, 2=spot)
    vec4 color;
    vec4 attenuation;
    vec4 spot_params;
};

layout(std430, set = 0, binding = 1) readonly buffer LightSSBO {
    int  numLights;
    int  _pad1, _pad2, _pad3;
    LightData lights[];
} lightSSBO;

// Set 1, Binding 0 — MSAA depth texture from depth prepass
layout(set = 1, binding = 0) uniform sampler2DMS depthTexture;

// Set 1, Binding 1 — light grid (output): uvec2(offset, count) per cluster
layout(std430, set = 1, binding = 1) writeonly buffer LightGrid {
    uvec2 clusters[];
} lightGrid;

// Set 1, Binding 2 — light index list (output): atomic counter + flat index array
layout(std430, set = 1, binding = 2) buffer LightIndexList {
    uint counter;
    uint _pad1, _pad2, _pad3;
    uint indices[];
} lightIndexList;

// Shared memory
shared uint tileMinDepthBits;
shared uint tileMaxDepthBits;

const uint MAX_LIGHTS_PER_CLUSTER = 128;
shared uint tileLightCount;
shared uint tileLightIndices[MAX_LIGHTS_PER_CLUSTER];

// Linearize depth from Vulkan NDC [0,1] to view-space distance
float linearizeDepth(float d) {
    return config.near_plane * config.far_plane
         / (config.far_plane - d * (config.far_plane - config.near_plane));
}

// Test sphere (point/spot light bounding volume) against AABB
bool sphereAABB(vec3 center, float radius, vec3 bMin, vec3 bMax) {
    vec3 closest = clamp(center, bMin, bMax);
    vec3 diff = center - closest;
    return dot(diff, diff) <= radius * radius;
}

void main() {
    uint tileX  = gl_WorkGroupID.x;
    uint tileY  = gl_WorkGroupID.y;
    uint localIdx = gl_LocalInvocationIndex; // 0..255

    // ---- Phase 1: Depth reduction ----
    if (localIdx == 0) {
        tileMinDepthBits = 0xFFFFFFFF;
        tileMaxDepthBits = 0;
    }
    barrier();

    uint pixelX = tileX * 16 + gl_LocalInvocationID.x;
    uint pixelY = tileY * 16 + gl_LocalInvocationID.y;

    if (pixelX < config.screen_width && pixelY < config.screen_height) {
        for (uint s = 0; s < config.sample_count; s++) {
            float depth = texelFetch(depthTexture, ivec2(pixelX, pixelY), int(s)).r;
            if (depth > 0.0 && depth < 1.0) {
                uint bits = floatBitsToUint(depth);
                atomicMin(tileMinDepthBits, bits);
                atomicMax(tileMaxDepthBits, bits);
            }
        }
    }
    barrier();

    // If tile has no valid depth, write empty clusters and exit
    if (tileMinDepthBits == 0xFFFFFFFF) {
        if (localIdx < config.depth_slices) {
            uint ci = tileX + tileY * config.tiles_x
                    + localIdx * config.tiles_x * config.tiles_y;
            lightGrid.clusters[ci] = uvec2(0, 0);
        }
        return;
    }

    float tileMinZ = linearizeDepth(uintBitsToFloat(tileMinDepthBits));
    float tileMaxZ = linearizeDepth(uintBitsToFloat(tileMaxDepthBits));

    // Tile frustum corners in NDC
    vec2 ndcMin = vec2(float(tileX * 16), float(tileY * 16))
                / vec2(float(config.screen_width), float(config.screen_height)) * 2.0 - 1.0;
    vec2 ndcMax = vec2(float(min((tileX + 1) * 16, config.screen_width)),
                       float(min((tileY + 1) * 16, config.screen_height)))
                / vec2(float(config.screen_width), float(config.screen_height)) * 2.0 - 1.0;

    // Unproject to view space at z=1 (direction vectors)
    mat4 invProj = inverse(camera.proj);
    vec4 vBL = invProj * vec4(ndcMin.x, ndcMin.y, 0.5, 1.0); vBL /= vBL.w;
    vec4 vTR = invProj * vec4(ndcMax.x, ndcMax.y, 0.5, 1.0); vTR /= vTR.w;

    uint numLights = uint(lightSSBO.numLights);

    // ---- Phase 2: Per-slice light culling ----
    for (uint slice = 0; slice < config.depth_slices; slice++) {
        if (localIdx == 0) {
            tileLightCount = 0;
        }
        barrier();

        // Compute slice depth range (exponential distribution)
        float t0 = float(slice) / float(config.depth_slices);
        float t1 = float(slice + 1) / float(config.depth_slices);
        float sliceNear = mix(tileMinZ, tileMaxZ, t0);
        float sliceFar  = mix(tileMinZ, tileMaxZ, t1);

        // Cluster AABB in view space
        // Scale the unprojected tile corners by slice depth range
        float refZ = abs(vBL.z);
        vec3 aabbMin = vec3(min(vBL.xy, vTR.xy) / refZ * sliceNear, -sliceFar);
        vec3 aabbMax = vec3(max(vBL.xy, vTR.xy) / refZ * sliceFar,  -sliceNear);

        // Each thread tests a subset of lights (stride = 256)
        for (uint li = localIdx; li < numLights; li += 256) {
            LightData light = lightSSBO.lights[li];
            uint lightType = uint(light.direction_type.w);

            bool hit = false;

            if (lightType == 0) {
                // Directional lights affect all clusters
                hit = true;
            } else {
                // Transform light position to view space
                vec3 posView = (camera.view * vec4(light.position_range.xyz, 1.0)).xyz;
                float range  = light.position_range.w;
                if (range <= 0.0) range = 50.0;
                hit = sphereAABB(posView, range, aabbMin, aabbMax);
            }

            if (hit) {
                uint idx = atomicAdd(tileLightCount, 1);
                if (idx < MAX_LIGHTS_PER_CLUSTER) {
                    tileLightIndices[idx] = li;
                }
            }
        }
        barrier();

        // Thread 0 writes this cluster's data to global buffers
        uint ci = tileX + tileY * config.tiles_x
                + slice * config.tiles_x * config.tiles_y;
        uint count = min(tileLightCount, MAX_LIGHTS_PER_CLUSTER);

        if (localIdx == 0) {
            if (count > 0) {
                uint globalOff = atomicAdd(lightIndexList.counter, count);
                lightGrid.clusters[ci] = uvec2(globalOff, count);
                for (uint i = 0; i < count; i++) {
                    lightIndexList.indices[globalOff + i] = tileLightIndices[i];
                }
            } else {
                lightGrid.clusters[ci] = uvec2(0, 0);
            }
        }
        barrier();
    }
}
