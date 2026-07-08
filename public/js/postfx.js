// Кинематографичный постпроцессинг: bloom (свечение), FXAA (сглаживание),
// цветокор + виньетка. Всё локально (аддоны three в ./three/), офлайн.
import * as THREE from './three.module.js';
import { EffectComposer } from './three/postprocessing/EffectComposer.js';
import { RenderPass } from './three/postprocessing/RenderPass.js';
import { ShaderPass } from './three/postprocessing/ShaderPass.js';
import { OutputPass } from './three/postprocessing/OutputPass.js';
import { UnrealBloomPass } from './three/postprocessing/UnrealBloomPass.js';
import { SSAOPass } from './three/postprocessing/SSAOPass.js';
import { FXAAShader } from './three/shaders/FXAAShader.js';

// финальный грейд: мягкий контраст, насыщенность, виньетка, лёгкое зерно
const GradeShader = {
  uniforms: {
    tDiffuse: { value: null },
    contrast: { value: 1.07 },
    saturation: { value: 1.12 },
    vignette: { value: 1.15 },
    grain: { value: 0.03 },
    time: { value: 0 },
  },
  vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
  fragmentShader: `
    uniform sampler2D tDiffuse; uniform float contrast, saturation, vignette, grain, time;
    varying vec2 vUv;
    float hash(vec2 p){ return fract(sin(dot(p, vec2(41.3,289.1))) * 43758.5453); }
    void main(){
      vec3 c = texture2D(tDiffuse, vUv).rgb;
      c = (c - 0.5) * contrast + 0.5;                       // контраст
      float l = dot(c, vec3(0.299, 0.587, 0.114));
      c = mix(vec3(l), c, saturation);                      // насыщенность
      vec2 d = vUv - 0.5;                                    // виньетка
      float v = smoothstep(0.9, 0.32, length(d) * vignette);
      c *= mix(0.68, 1.0, v);
      c += (hash(vUv + fract(time)) - 0.5) * grain;         // тонкое зерно
      gl_FragColor = vec4(clamp(c, 0.0, 1.0), 1.0);
    }`,
};

export function makeComposer(renderer, scene, camera) {
  const composer = new EffectComposer(renderer);
  composer.setPixelRatio(1);           // постпроцессинг в CSS-пикселях — вчетверо дешевле на hi-dpi

  const renderPass = new RenderPass(scene, camera);
  composer.addPass(renderPass);

  // SSAO — контактные тени в углах/стыках. Тяжёлый, потому выключен по умолчанию;
  // включается только на сильном GPU (см. авто-замер в main.js) или вручную клавишей O.
  const ssao = new SSAOPass(scene, camera, window.innerWidth, window.innerHeight);
  ssao.kernelRadius = 0.7;
  ssao.minDistance = 0.003;
  ssao.maxDistance = 0.10;
  ssao.enabled = false;
  composer.addPass(ssao);

  const bloom = new UnrealBloomPass(
    new THREE.Vector2(window.innerWidth * 0.5, window.innerHeight * 0.5), // bloom в полразрешения
    0.38,   // strength — мягче, чтобы небо/солнце не раздувалось в слепящий ореол
    0.5,    // radius
    0.88    // threshold — светятся только очень яркие/эмиссивные (муззл, способности, металл)
  );
  composer.addPass(bloom);

  const output = new OutputPass();     // тон-маппинг ACES + sRGB
  composer.addPass(output);

  const fxaa = new ShaderPass(FXAAShader);
  composer.addPass(fxaa);

  const grade = new ShaderPass(GradeShader);
  composer.addPass(grade);

  const setSize = (w, h) => {
    composer.setSize(w, h);
    bloom.setSize(w * 0.5, h * 0.5);
    ssao.setSize(w, h);
    fxaa.material.uniforms.resolution.value.set(1 / w, 1 / h);
  };
  setSize(window.innerWidth, window.innerHeight);

  // включить/выключить SSAO без двойного рендера сцены: renderPass и ssao взаимоисключающи
  const setSSAO = (on) => { ssao.enabled = on; renderPass.enabled = !on; };

  return {
    composer, bloom, grade, ssao, setSSAO,
    ssaoOn: () => ssao.enabled,
    setSize,
    render: (dt) => { grade.material.uniforms.time.value += dt; composer.render(); },
  };
}
