## LDJ.jl

This package implements wrappers for [schema.org](https://schema.org) structured data markup according to [google](https://developers.google.com/search/docs/advanced/structured-data) guidelines.

It tries to generate templates, with kw args to fill some parameters.

## Usage

``` julia
using LDJ
author(;name="Puffy", email="contact@example.com") |> wrap_ldj
```

