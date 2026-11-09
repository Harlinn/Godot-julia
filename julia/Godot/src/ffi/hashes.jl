# Copyright 2026 Espen Harlinn
# SPDX-License-Identifier: Apache-2.0

# Method hash lookup backed by generated/method_hashes.tsv (loaded lazily on first use).

const HASHES_FILE = joinpath(GENERATED_DIR, "method_hashes.tsv")
include_dependency(HASHES_FILE)

const HASHES = Dict{Tuple{Symbol, Symbol, Symbol}, Int64}()
const HASHES_LOCK = ReentrantLock()

function load_hashes!()
    for line in eachline(HASHES_FILE)
        kind, owner, name, hash = split(line, '\t')
        HASHES[(Symbol(kind), Symbol(owner), Symbol(name))] = parse(Int64, hash)
    end
    return nothing
end

function lookup_hash(kind::Symbol, owner::Symbol, name::Symbol)
    @lock HASHES_LOCK begin
        isempty(HASHES) && load_hashes!()
        h = get(HASHES, (kind, owner, name), nothing)
        h === nothing && throw(KeyError((kind, owner, name)))
        return h
    end
end

"Hash of the engine method `class.method` as listed in extension_api.json."
method_hash(class::Symbol, method::Symbol) = lookup_hash(:class, class, method)

"Hash of the builtin-type method `type.method` (e.g. `:String`, `:length`)."
builtin_method_hash(type::Symbol, method::Symbol) = lookup_hash(:builtin, type, method)

"Hash of the global utility function `name` (e.g. `:sin`)."
utility_hash(name::Symbol) = lookup_hash(:utility, Symbol(""), name)
