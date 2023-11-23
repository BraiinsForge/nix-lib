craneLib: [
  (craneLib.registryFromGitIndex {
    indexUrl = "git://kellnr.ii.zone/index";
    rev = "a7d5bb570eaa2eeebd233b4dab16452200df5966";
  })
  (craneLib.registryFromSparse {
    indexUrl = "http://registry.ii.zone:8000/api/v1/crates/";
    configSha256 = "93d873d35cbea1f4accd8f86a22594451a68129ea58800ca7442d5f184271d44";
  })
  (craneLib.registryFromSparse {
    indexUrl = "http://registry.ii.zone/api/v1/crates/";
    configSha256 = "93d873d35cbea1f4accd8f86a22594451a68129ea58800ca7442d5f184271d44";
  })
]
