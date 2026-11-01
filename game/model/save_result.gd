class_name SaveResult
extends RefCounted
## Outcome of an encode, decode, save or load. Plain record, no Node.
##
## NOT_FOUND means "not found or unreadable". INTERNAL is a programming error (a model the writer
## refuses, a bad argument or a re-entrant call): nothing was touched and nothing was written.
## detail is for developers only and is never shown to the player.

enum Kind { OK, NOT_FOUND, DAMAGED, NEWER_VERSION, PATH_REFUSED, WRITE_FAILED, INTERNAL }

var kind: Kind = Kind.INTERNAL
## Set only by a successful decode.
var model: AquariumModel = null
## Set only by a successful encode.
var text: String = ""
var detail: String = ""


func is_ok() -> bool:
	return kind == Kind.OK


## OK with neither model nor text (a save or load that has nothing to hand back).
static func success() -> SaveResult:
	var result: SaveResult = SaveResult.new()
	result.kind = Kind.OK
	return result


static func with_model(value: AquariumModel) -> SaveResult:
	var result: SaveResult = SaveResult.new()
	result.kind = Kind.OK
	result.model = value
	return result


static func with_text(value: String) -> SaveResult:
	var result: SaveResult = SaveResult.new()
	result.kind = Kind.OK
	result.text = value
	return result


static func failure(failure_kind: Kind, why: String) -> SaveResult:
	var result: SaveResult = SaveResult.new()
	result.kind = failure_kind
	result.detail = why
	return result
