import raylib, sequtils, math, strutils

type
  Tile = object
    id: int
    solid: bool

  TileMap = object
    tiles: seq[seq[Tile]]
    tileSize: int32
    tilesetTexture: Texture2D
    tilesetColumns: int32

  Window = object
    x: int32
    y: int32
    title: string
  
  Game = object
    window: Window
    camera: Camera2D
    tilemap: TileMap
    running: bool

proc newTile(id: int, solid: bool = false): Tile =
  result.id = id
  result.solid = solid

proc newTileMap(width, height, tileSize: int32): Tilemap =
  result.tileSize = tileSize
  result.tiles = newSeqWith(height.int, newSeq[Tile](width.int))
  result.tilesetColumns = 1 # Default, update when loading a texture

proc newCamera(): Camera2D =
  result.offset = Vector2(x: 0, y: 0)
  result.target = Vector2(x: 0, y: 0)
  result.rotation = 0.0
  result.zoom = 1.0

proc newWindow(x, y: int32, title: string): Window =
  result.x = x
  result.y = y
  result.title = title

proc newGame(): Game =
  result.window = newWindow(800, 600, "Raylib App")
  result.camera = newCamera()
  result.tilemap = newTileMap(5, 5, 16)
  result.running = true

proc loadTileset(tilemap: var TileMap, filename: string, columns: int32) =
  tilemap.tilesetTexture = loadTexture(filename)
  tilemap.tilesetColumns = columns

proc setTile(tilemap: var TileMap, x, y, id: int, solid: bool = false) =
  if x >= 0 and x <= tilemap.tiles[0].len and y >= 0 and y <= tilemap.tiles.len:
    tilemap.tiles[y][x] = newTile(id, solid)

proc getTile(tilemap: TileMap, x, y: int): Tile =
  if x >= 0 and x <= tilemap.tiles[0].len and y >= 0 and y <= tilemap.tiles.len:
    return tilemap.tiles[y][x]
  return newTile(0) # Return default tile

proc loadTilemapCSV(pathTilemap, pathCollisionMap: string, tilemap: var Tilemap) =
  let tileData = readFile(pathTilemap).strip().split("\n")
  let collisionData = readFile(pathCollisionMap).strip().split("\n")

  for y, row in tileData:
    let tiles = row.split(",")
    let collisions = collisionData[y].split(",")

    for x, tile in tiles:
      let tileId = parseInt(tile.strip())
      let solid = parseInt(collisions[x].strip()) == 1  # Read solid from the second CSV
      tilemap.setTile(x, y, tileId, solid)

proc tileToScreen(tilemap: TileMap, tileX, tileY: int): Vector2 =
  result.x = tileX.float32 * tilemap.tileSize.float32
  result.y = tileY.float32 * tilemap.tileSize.float32

proc screenToTile(tilemap: TileMap, screenX, screenY: float32): tuple[x, y: int] =
  result.x = (screenX / tilemap.tileSize.float32).int
  result.y = (screenY / tilemap.tileSize.float32).int

proc getTileSourceRect(tilemap: Tilemap, id: int): Rectangle =
  let
    tilesPerRow = tilemap.tilesetColumns
    tileX = (id mod tilesPerRow).int32
    tileY = (id div tilesPerRow).int32

  result.x = tileX.float32 * tilemap.tileSize.float32
  result.y = tileY.float32 * tilemap.tileSize.float32
  result.width = tilemap.tileSize.float32
  result.height = tilemap.tileSize.float32

proc initGame(game: var Game) =
  initWindow(game.window.x, game.window.y, "Raylib App")

  loadTileset(game.tilemap, "assets/tileset.png", 2)
  
  loadTilemapCSV("tilemaps/tilemap.csv", "tilemaps/collisionmap.csv", game.tilemap)

proc handleInput(game: var Game) =
  if isKeyDown(KeyboardKey.Right):
    game.camera.target.x += 0.5
  if isKeyDown(KeyboardKey.Left):
    game.camera.target.x -= 0.5
  if isKeyDown(KeyboardKey.Down):
    game.camera.target.y += 0.5
  if isKeyDown(KeyboardKey.Up):
    game.camera.target.y -= 0.5

  if isKeyPressed(KeyboardKey.Equal):
    game.camera.zoom += 0.1
  if isKeyPressed(KeyboardKey.Minus):
    game.camera.zoom -= 0.1
    if game.camera.zoom < 0.1:
      game.camera.zoom = 0.1

proc update(game: var Game) =
  if windowShouldClose():
    game.running = false

proc renderTilemap(game: Game) =
  let
    tileSize = game.tilemap.tileSize.float32

    startTileX = max(0, (game.camera.target.x / tileSize).int)
    startTileY = max(0, (game.camera.target.y / tileSize).int)

    visibleTilesX = (game.window.x.float32 / game.camera.zoom / tileSize).int + 2
    visibleTilesY = (game.window.y.float32 / game.camera.zoom / tileSize).int + 2

    endTileX = min(game.tilemap.tiles[0].len - 1, startTileX + visibleTilesX)
    endTileY = min(game.tilemap.tiles.len - 1, startTileY + visibleTilesY)

  # Only render tiles that are visible
  for y in startTileY..endTileY:
    for x in startTileX..endTileX:
      let
        tile = game.tilemap.tiles[y][x]
        pos = Vector2(
          x: (x.float32 * tileSize),
          y: (y.float32 * tileSize)
        )

      if game.tilemap.tilesetTexture.id != 0 and tile.id != 0:
        let
          sourceRect = game.tilemap.getTileSourceRect(tile.id)
          destRect = Rectangle(
            x: pos.x,
            y: pos.y,
            width: tileSize,
            height: tileSize
          )

        drawTexture(
          game.tilemap.tilesetTexture,
          sourceRect,
          destRect,
          Vector2(x: 0, y: 0),
          0.0,
          White
        )
      else:
        # Fallback - render colored rectangles
        let
          color = if tile.solid: Gray else: LightGray
          xPos = floor(pos.x).int32
          yPos = floor(pos.y).int32
          width = tileSize.int32 + 1
          height = tileSize.int32 + 1

        drawRectangle(xPos, yPos, width, height, color)
  
proc render(game: var Game) =
  beginDrawing()
  clearBackground(RayWhite)

  let originalCamera = game.camera

  # Adjust camera for pixel-perfect rendering
  var adjustedCamera = game.camera
  adjustedCamera.target.x = floor(game.camera.target.x)
  adjustedCamera.target.y = floor(game.camera.target.y)

  beginMode2D(adjustedCamera)
  renderTilemap(game)
  endMode2D()

  drawFPS(10, 10)
  drawText("Arrow keys: Move | +/-: Zoom", 10, 30, 20, DarkGray)
  
  endDrawing()

proc cleanup(game: var Game) =
  closeWindow()

proc runGame(game: var Game) =
  initGame(game)
  
  while game.running:
    handleInput(game)
    update(game)
    render(game)

  cleanup(game)

proc main() =
  var game: Game = newGame()
  runGame(game)

when isMainModule:
  main()
