{ runCommand, llmWithPlugins, cacert, lib, stdenv }:

runCommand "llm-runtime" { } ''
  export HOME=$TMPDIR/home
  mkdir -p "$HOME"
  export OPENBLAS_NUM_THREADS=1
  export SSL_CERT_FILE=${cacert}/etc/ssl/certs/ca-bundle.crt
  ${llmWithPlugins}/bin/llm plugins > plugins.json
  ${llmWithPlugins}/bin/llm models list > models.txt
  ${llmWithPlugins}/bin/python3 <<'PY'
  import json
  import numpy as np
  from numpy.testing import assert_allclose
  from llama_cpp import llama_cpp

  plugins = {p["name"] for p in json.load(open("plugins.json"))}
  assert {
      "llm-ollama", "llm-gguf", "llm-openrouter", "llm-docs", "llm-llama-server"
  } <= plugins, plugins
  ${lib.optionalString (stdenv.hostPlatform.isDarwin && stdenv.hostPlatform.isAarch64) ''
  assert "llm-mlx" in plugins, plugins
  import mlx.core
  ''}

  # Exercise BLAS matrix multiplication and LAPACK solves/decompositions in
  # all four real/complex precisions. Large enough to enter BLAS, with known
  # solutions and reconstruction checks rather than just import/version.
  rng = np.random.default_rng(42)
  for dtype in (np.float32, np.float64, np.complex64, np.complex128):
      a = rng.normal(size=(64, 64)).astype(dtype)
      if np.issubdtype(dtype, np.complexfloating):
          a += 1j * rng.normal(size=a.shape).astype(dtype)
      a = a @ a.conj().T + 64 * np.eye(64, dtype=dtype)
      x = rng.normal(size=(64, 4)).astype(dtype)
      b = a @ x
      tol = 2e-5 if dtype in (np.float32, np.complex64) else 1e-12
      assert_allclose(np.linalg.solve(a, b), x, rtol=tol, atol=tol)
      u, s, vh = np.linalg.svd(a)
      assert_allclose((u * s) @ vh, a, rtol=tol, atol=tol * 100)
      w, v = np.linalg.eigh(a)
      assert_allclose((v * w) @ v.conj().T, a, rtol=tol, atol=tol * 100)
      q, r = np.linalg.qr(a)
      assert_allclose(q @ r, a, rtol=tol, atol=tol * 100)
  np.show_config()

  # Load the native GGUF backend too; no downloaded model or API key needed.
  llama_cpp.llama_backend_init()
  assert llama_cpp.llama_print_system_info()
  llama_cpp.llama_backend_free()
  print("llm plugins, NumPy BLAS/LAPACK, and llama.cpp backend passed")
  PY
  touch "$out"
''
