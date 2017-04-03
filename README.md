SwiftBeaker
===========

Swift client generator for API Blueprint

## Usage

```sh
% drafter -f json api-blueprint-document.md > apib.json # generate AST using drafter
% SwiftBeaker apib.json > APIClient.swift
```

## Conversion

SwiftBeaker converts ...

* each Transitions into a [APIKit](https://github.com/ishkawa/APIKit)`.Request`
* each Responses bound to a Request into a `enum Responses` whose cases identified by a pair of status code and content type
* each Data Structures (named and anonymous) into a [Himotoki](https://github.com/ikesyo/Himotoki)`.Decodable` struct

## TODO

- [ ] support content type other than `application/json`
- [ ] support URITemplate style endpoint

