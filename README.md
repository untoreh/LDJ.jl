## LDJ.jl

This package implements wrappers for [schema.org](https://schema.org) structured data markup according to [google](https://developers.google.com/search/docs/advanced/structured-data) guidelines.

It tries to generate templates, with kw args to fill some parameters.

## Usage

``` julia
using LDJ
author(;name="Puffy", email="contact@example.com") |> wrap_ldj
```

## Franklin
There are functions to add schema markup under the `LDJFranklin` module that work with franklin global or page variables.

## Calibre
It is possible to generate a list of books as a _library_ entity from a calibre content server. (Although this is not exactly what google has in mind for libraries :) )
