# SPDX-FileCopyrightText: Copyright © contributors to CloudNativePG, established as CloudNativePG a Series of LF Projects, LLC.
# SPDX-License-Identifier: Apache-2.0
metadata = {
  name                     = "citus"
  sql_name                 = "citus"
  image_name               = "citus"

  # Citus has no upstream "or later" grant in its source headers, so it is
  # tracked as the exact AGPL-3.0 version distributed in its LICENSE file.
  # NOTE: AGPL-3.0 is not on the CNCF license allowlist; see the
  # CONTRIBUTING_NEW_EXTENSION.md governance note before upstreaming this.
  licenses                 = ["AGPL-3.0-only"]

  shared_preload_libraries = ["citus"]

  postgresql_parameters    = {}

  extension_control_path   = []

  dynamic_library_path     = []

  # citus.so is linked against libcurl (pulled in transitively because
  # PostgreSQL core on this base image is built --with-libcurl, which makes
  # Citus' statistics_collection.c compile its curl-dependent code path
  # regardless of Citus' own --with(out)-libcurl configure flag). libcurl
  # and the handful of its transitive dependencies not already shipped in
  # the base image are vendored under the image's `system` directory; see
  # the `postgis` extension for the same pattern.
  ld_library_path          = ["system"]

  bin_path                 = []

  env = {}

  # Allows the maintenance tooling to bump the vendored libcurl/system
  # libraries automatically, same as `postgis`.
  auto_update_os_libs      = true

  # citus.control declares `requires = 'citus_columnar'`, but that is the
  # bundled citus_columnar extension shipped in the same source tree/image,
  # not a sibling folder in this repository, so it is not listed here.
  required_extensions      = []

  create_extension         = true

  # NOTE: Citus has no PGDG/Debian package, so it is built from the upstream
  # GitHub release tarball (v${package}.tar.gz) instead. The repo's renovate
  # `.hcl` custom manager only understands the `deb` datasource, so this
  # version is NOT tracked automatically yet and must be bumped by hand when
  # a new upstream release ships.
  versions = {
    trixie = {
        "18" = {
          package = "14.2.0"
          sql = "14.2-1"
        }
    }
    bookworm = {
        "18" = {
          package = "14.2.0"
          sql = "14.2-1"
        }
    }
  }
}
