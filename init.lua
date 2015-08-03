require 'cutorch'
require 'nn'
cudnn = require 'cudnn.env'
include 'ffi.lua'
local C = cudnn.C
local ffi = require 'ffi'

local maxStreamsPerDevice = 1024
local numDevices = cutorch.getDeviceCount()
-- this tensor keeps track of whether a handle has been initialized or not
local handleStatus = torch.ByteTensor(numDevices,
                                  maxStreamsPerDevice):zero()
-- here we create an array of cudnn handle structs
cudnn.handle = ffi.new('struct cudnnContext*[?]', numDevices*maxStreamsPerDevice)
local function destroy(handle)
    local currentDevice = cutorch.getDevice()
    for i=1,numDevices do
        cutorch.setDevice(i)
        -- streams go from 0 to maxStreamsPerDevice - 1
        for j=0,maxStreamsPerDevice - 1 do
            if handleStatus[i][j + 1] == 1 then -- if handle was created
                errcheck('cudnnDestroy', handle[(((i-1)*maxStreamsPerDevice) + j)]);
            end
        end
    end
    cutorch.setDevice(currentDevice)
end
ffi.gc(cudnn.handle, destroy)

function cudnn.getHandle()
    local device = cutorch.getDevice()
    local stream = cutorch.getStream() -- starts from 0
    assert(stream < maxStreamsPerDevice, 'cudnn bindings only support max of : '
               .. maxStreamsPerDevice .. ' streams per device')
    -- lazy initialization of handles
    if handleStatus[device][stream + 1] == 0 then
        local status = C['cudnnCreate'](cudnn.handle
                                        + (((device-1) * maxStreamsPerDevice)
                                                + stream))
        if status ~= ffi.C.CUDNN_STATUS_SUCCESS then
            local str = ffi.string(C.cudnnGetErrorString(status))
            error('Error in CuDNN: ' .. str)
        end
        handleStatus[device][stream + 1] = 1 -- mark handle as initialized
    end
    return cudnn.handle[(((device-1)*maxStreamsPerDevice) + stream)]
end

local errcheck = function(f, ...)
    C.cudnnSetStream(cudnn.getHandle(),
                     ffi.C.THCState_getCurrentStream(cutorch.getState()))
   local status = C[f](...)
   if status ~= ffi.C.CUDNN_STATUS_SUCCESS then
      local str = ffi.string(C.cudnnGetErrorString(status))
      error('Error in CuDNN: ' .. str)
   end
end
cudnn.errcheck = errcheck

function cudnn.toDescriptor(t)
   assert(torch.typename(t) == 'torch.CudaTensor')
   local descriptor = ffi.new('struct cudnnTensorStruct*[1]')
   -- create descriptor
   errcheck('cudnnCreateTensorDescriptor', descriptor)
   -- set gc hook
   local function destroy(d)
      errcheck('cudnnDestroyTensorDescriptor', d[0]);
   end
   ffi.gc(descriptor, destroy)
   -- set descriptor
   local size = torch.LongTensor(t:size()):int()
   local stride = torch.LongTensor(t:stride()):int()
   errcheck('cudnnSetTensorNdDescriptor', descriptor[0], 'CUDNN_DATA_FLOAT',
            t:dim(), size:data(), stride:data())
   return descriptor
end

include 'SpatialConvolution.lua'
include 'VolumetricConvolution.lua'
include 'Pooling.lua'
include 'SpatialMaxPooling.lua'
include 'SpatialAveragePooling.lua'
include 'Pointwise.lua'
include 'ReLU.lua'
include 'Tanh.lua'
include 'Sigmoid.lua'
include 'SpatialSoftMax.lua'
include 'SpatialLogSoftMax.lua'
include 'SoftMax.lua'
include 'LogSoftMax.lua'
include 'SpatialCrossMapLRN.lua'

include 'functional.lua'

return cudnn
