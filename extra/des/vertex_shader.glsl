#version 330 core

layout(location = 0) in vec3 position;
layout(location = 1) in vec3 color;

uniform mat4 model;
uniform mat4 view;
uniform mat4 projection;

out vec3 fragColor;

void main() {
    fragColor = color;
    gl_Position = projection * view * model * vec4(position, 1.0);
}
