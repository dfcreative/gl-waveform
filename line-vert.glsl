precision highp float;

attribute float id, sign;

uniform sampler2D data0, data1;
uniform float opacity, thickness, step, textureId, total, samplesPerStep;
uniform vec2 scale, translate, dataShape;
uniform vec4 viewport, color;
uniform float sum, sum2, dataLength;

varying vec4 fragColor;

const float lessThanThickness = 0.;

// linear interpolation
vec4 lerp(vec4 a, vec4 b, float t) {
	return t * b + (1. - t) * a;
}
vec2 lerp(vec2 a, vec2 b, float t) {
	return t * b + (1. - t) * a;
}

vec4 pickSample (float offset, float baseOffset) {
	vec2 uv = vec2(
		mod(offset, dataShape.x) + .5,
		floor(offset / dataShape.x) + .5
	) / dataShape;

	uv.y -= textureId;

	if (uv.y > 1.) {
		uv.y = uv.y - 1.;

		vec4 sample = texture2D(data1, uv);

		// if right sample is from the next texture - align it to left texture
		if (offset >= dataLength && baseOffset < dataLength) {
			sample.y += sum;
			sample.z += sum2;
		}

		return sample;
	}
	else return texture2D(data0, uv);
}

// pick sample from the source texture
vec4 pick(float id, float baseId) {
	float offset = id * samplesPerStep;
	float baseOffset = baseId * samplesPerStep;

	// offset = min(offset, total - 1.);

	float offsetLeft = floor(offset);
	float offsetRight = ceil(offset);
	float t = offset - offsetLeft;

	if (offsetLeft == offsetRight) {
		offsetRight = ceil(offset + .5);
		t = 0.;
	}

	vec4 left = pickSample(offsetLeft, baseOffset);
	vec4 right = pickSample(offsetRight, baseOffset);

	return lerp(left, right, t);
}

void main() {
	gl_PointSize = 3.;

	// FIXME: make end point cut more elegant
	if (translate.x + id * samplesPerStep >= total - 1.) return;

	// calc average of curr..next sampling points
	float translateInt = floor(translate.x / samplesPerStep);
	float sampleId = id + translateInt;
	vec4 sample0 = pick(sampleId, sampleId - 1.);
	vec4 sample1 = pick(sampleId + 1., sampleId - 1.);

	float avgCurr = (sample1.y - sample0.y) / samplesPerStep;

	float variance = 0., sdev = 0.;

	// only scales more than 1 skip steps
	// if (scale.x * viewport.z < 1.) {
		// σ² = M(x²) - M²
		variance = abs(
			// (sample1.z - sample0.z) / samplesPerStep - avgCurr * avgCurr
			((sample1.z - sample0.z) - (sample1.y - sample0.y) * (sample1.y - sample0.y) / samplesPerStep) / samplesPerStep
		);
		sdev = sqrt(variance);
	// }

	// compensate for sampling rounding
	float translateOff = translate.x / samplesPerStep - translateInt;
	vec2 position = vec2(.5 * step * (id - translateOff) / viewport.z, avgCurr * .5 + .5);

	vec4 samplePrev = pick(sampleId - 1., sampleId - 1.);
	vec4 sampleNext = pick(sampleId + 2., sampleId - 1.);

	float avgPrev = (sample0.y - samplePrev.y) / samplesPerStep;
	float avgNext = (sampleNext.y - sample1.y) / samplesPerStep;

	float x = .5 * step / viewport.z;
	vec2 normalLeft = normalize(vec2(
		-(avgCurr - avgPrev) * .5, x
	) / viewport.zw);
	vec2 normalRight = normalize(vec2(
		-(avgNext - avgCurr) * .5, x
	) / viewport.zw);

	vec2 bisec = normalize(normalLeft + normalRight);
	vec2 vert = vec2(0, 1);
	float bisecLen = abs(1. / dot(normalLeft, bisec));
	float vertRightLen = abs(1. / dot(normalRight, vert));
	float vertLeftLen = abs(1. / dot(normalLeft, vert));
	float maxVertLen = max(vertLeftLen, vertRightLen);
	float minVertLen = min(vertLeftLen, vertRightLen);
	float vertSdev = 2. * sdev * viewport.w / thickness;

	vec2 join;

	// sdev less than projected to vertical shows simple line
	if (vertSdev < maxVertLen) {
		// sdev more than normal but less than vertical threshold
		// rotates join towards vertical
		if (vertSdev > minVertLen) {
			float t = (vertSdev - minVertLen) / (maxVertLen - minVertLen);
			join = lerp(bisec * bisecLen, vert * maxVertLen, t);
		}
		else {
			join = bisec * bisecLen;
		}
	}
	// sdev more than projected to vertical modifies only y coord
	else {
		join = vert * vertSdev;
	}

	position += sign * join * .5 * thickness / viewport.zw;
	gl_Position = vec4(position * 2. - 1., 0, 1);

	fragColor = color / 255.;

	if (translate.x + id * samplesPerStep > dataLength) {
		fragColor.x *= .5;
	}

	fragColor.a *= opacity;
}
