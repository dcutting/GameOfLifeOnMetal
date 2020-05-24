import MetalKit
import PlaygroundSupport

class Renderer: NSObject {
  let mtkView: MTKView
  let commandQueue: MTLCommandQueue
  let vertexData: [Float]
  let vertexBuffer: MTLBuffer
  let renderState: MTLRenderPipelineState
  let computeState: MTLComputePipelineState
  var generationA: MTLTexture
  var generationB: MTLTexture
  var cellsWide = 100
  var cellsHigh = 100
  var cellSize = 4
  var generation = 0
  
  override init() {
    let device = MTLCreateSystemDefaultDevice()!
    self.commandQueue = device.makeCommandQueue()!
    
    let frame = CGRect(x: 0, y: 0,
                       width: cellsWide * cellSize,
                       height: cellsHigh * cellSize)
    self.mtkView = MTKView(frame: frame, device: device)

    vertexData = [-1.0, -1.0, 0.0, 1.0,
                   1.0, -1.0, 0.0, 1.0,
                  -1.0,  1.0, 0.0, 1.0,
                  -1.0,  1.0, 0.0, 1.0,
                   1.0, -1.0, 0.0, 1.0,
                   1.0,  1.0, 0.0, 1.0]
    let dataSize = vertexData.count * MemoryLayout<Float>.size
    vertexBuffer = device.makeBuffer(bytes: vertexData,
                                     length: dataSize,
                                     options: [])!
    
    let file = Bundle.main.path(forResource: "Shaders", ofType: "metal")!
    let source = try! String(contentsOfFile: file, encoding: .utf8)

    let library = try! device.makeLibrary(source: source, options: nil)
    let vertexFn = library.makeFunction(name: "vertex_shader")
    let fragmentFn = library.makeFunction(name: "fragment_shader")
    
    let renderDesc = MTLRenderPipelineDescriptor()
    renderDesc.vertexFunction = vertexFn
    renderDesc.fragmentFunction = fragmentFn
    renderDesc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
    renderState = try! device.makeRenderPipelineState(descriptor: renderDesc)
    
    let computeFn = library.makeFunction(name: "generation")!
    computeState = try! device.makeComputePipelineState(function: computeFn)
    
    (generationA, generationB) = Self.makeTextures(device: device,
                                     width: cellsWide,
                                     height: cellsHigh)
    
    super.init()
    
    mtkView.delegate = self
    
    restart(random: true)
  }
  
  func currentGenerationTexture() -> MTLTexture {
    generation % 2 == 0 ? generationA : generationB
  }
  
  func nextGenerationTexture() -> MTLTexture {
    generation % 2 == 0 ? generationB : generationA
  }
  
  static func makeTextures(device: MTLDevice,
                           width: Int,
                           height: Int) -> (MTLTexture, MTLTexture) {
    let textureDescriptor = MTLTextureDescriptor()
    textureDescriptor.storageMode = .managed
    textureDescriptor.usage = [.shaderWrite, .shaderRead]
    textureDescriptor.pixelFormat = .r8Uint
    textureDescriptor.width = width
    textureDescriptor.height = height
    textureDescriptor.depth = 1
    
    let generationA = device.makeTexture(descriptor: textureDescriptor)!
    let generationB = device.makeTexture(descriptor: textureDescriptor)!
    
    return (generationA, generationB)
  }

  func restart(random: Bool) {
    generation = 0
    var seed = [UInt8](repeating: 0, count: cellsWide * cellsHigh)
    if random {
      let numberOfCells = cellsWide * cellsHigh
      let numberOfLiveCells = Int(pow(Double(numberOfCells), 0.8))
      for _ in (0..<numberOfLiveCells) {
        let r = (0..<numberOfCells).randomElement()!
        seed[r] = 1
      }
    }
    currentGenerationTexture().replace(
      region: MTLRegionMake2D(0, 0, cellsWide, cellsHigh),
      mipmapLevel: 0,
      withBytes: seed,
      bytesPerRow: cellsWide * MemoryLayout<UInt8>.stride
    )
  }
}

extension Renderer: MTKViewDelegate {

  func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
  
  func draw(in view: MTKView) {
    guard
      let buffer = commandQueue.makeCommandBuffer(),
      let desc = view.currentRenderPassDescriptor,
      let renderEncoder = buffer.makeRenderCommandEncoder(descriptor: desc)
      else { return }
    
    renderEncoder.setRenderPipelineState(renderState)
    renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    renderEncoder.setFragmentTexture(currentGenerationTexture(), index: 0)
    renderEncoder.drawPrimitives(type: .triangle,
                                 vertexStart: 0,
                                 vertexCount: 6)
    renderEncoder.endEncoding()
    
    guard
      let computeEncoder = buffer.makeComputeCommandEncoder()
      else { return }
    
    computeEncoder.setComputePipelineState(computeState)
    computeEncoder.setTexture(currentGenerationTexture(), index: 0)
    computeEncoder.setTexture(nextGenerationTexture(), index: 1)
    let threadWidth = computeState.threadExecutionWidth
    let threadHeight = computeState.maxTotalThreadsPerThreadgroup / threadWidth
    let threadsPerThreadgroup = MTLSizeMake(threadWidth, threadHeight, 1)
    let threadsPerGrid = MTLSizeMake(cellsWide, cellsHigh, 1)
    computeEncoder.dispatchThreads(threadsPerGrid,
                                   threadsPerThreadgroup: threadsPerThreadgroup)
    computeEncoder.endEncoding()
      
    if let drawable = view.currentDrawable {
      buffer.present(drawable)
    }
    buffer.commit()

    generation += 1
  }
}

let renderer = Renderer()

PlaygroundPage.current.liveView = renderer.mtkView
