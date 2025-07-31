{ runtimeShell
, lib
, runCommand
, runtimeDeps ? [ ]
, wrapNixGL ? false
, mesa ? null
, libglvnd ? null
, ...
}: (''
  #!${runtimeShell}
  export LD_LIBRARY_PATH=${lib.makeLibraryPath runtimeDeps}:$LD_LIBRARY_PATH
'' + lib.optionalString wrapNixGL (
  let
    glxindirect = runCommand "mesa_glxindirect" { }
      ''
        mkdir -p $out/lib
        ln -s ${mesa}/lib/libGLX_mesa.so.0 $out/lib/libGLX_indirect.so.0
      ''
    ;
  in
  # Do nixGL magic (some if this is probably not needed)
    # Heavily inspired by nixGL: https://github.com/nix-community/nixGL/blob/a8e1ce7d49a149ed70df676785b07f63288f53c5/nixGL.nix#L40
  ''
    export GBM_BACKENDS_PATH=${lib.makeSearchPathOutput "lib" "lib/gbm" [mesa]}
    export LIBGL_DRIVERS_PATH=${lib.makeSearchPathOutput "lib" "lib/dri" [mesa]}
    export LIBVA_DRIVERS_PATH=${lib.makeSearchPathOutput "out" "lib/dri" [mesa]}
    ${''export __EGL_VENDOR_LIBRARY_FILENAMES=${mesa.drivers}/share/glvnd/egl_vendor.d/50_mesa.json"''${__EGL_VENDOR_LIBRARY_FILENAMES:+:$__EGL_VENDOR_LIBRARY_FILENAMES}"''}
    export LD_LIBRARY_PATH=${lib.makeLibraryPath ([mesa] ++ runtimeDeps)}:${glxindirect}/lib:${lib.makeLibraryPath [libglvnd]}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  ''
))
