craneLib: [
  (craneLib.registryFromGitIndex {
    indexUrl = "git://kellnr.ii.zone/index";
    rev = "a7d5bb570eaa2eeebd233b4dab16452200df5966";
  })
  (craneLib.registryFromSparse {
    indexUrl = "http://registry.ii.zone:8000/api/v1/crates/";
    configSha256 = "8ae51bd02f2645c885a8595e2c0bda4baf2855992b38b57328b444b9132ef1df";
  })
  (craneLib.registryFromSparse {
    indexUrl = "http://registry.ii.zone/api/v1/crates/";
    configSha256 = "8ae51bd02f2645c885a8595e2c0bda4baf2855992b38b57328b444b9132ef1df";
  })
]
