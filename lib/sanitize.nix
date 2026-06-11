# Turn an upstream version string into a valid (and readable) Nix attr suffix.
#   "3.24.0"          -> "3_24_0"
#   "3.45.0-0.1.pre"  -> "3_45_0_0_1_pre"
version: builtins.replaceStrings [ "." "-" "+" ] [ "_" "_" "_" ] version
