from util.utils import get_som_labeled_img, get_caption_model_processor, get_yolo_model, check_ocr_box
import os
import time
import threading
import torch
from PIL import Image
import io
import base64
from typing import Dict

# GPU memory management modes:
#   persistent - models stay on GPU permanently (default, original behavior)
#   ondemand   - models on CPU, moved to GPU per request, offloaded after idle timeout
#   cpu        - GPU never used
GPU_MODE = os.environ.get('OMNIPARSER_GPU_MODE', 'persistent')
GPU_IDLE_TIMEOUT = int(os.environ.get('OMNIPARSER_GPU_IDLE_TIMEOUT', '30'))


class Omniparser(object):
    def __init__(self, config: Dict):
        self.config = config
        self.gpu_mode = GPU_MODE
        self.gpu_idle_timeout = GPU_IDLE_TIMEOUT
        self._offload_timer = None
        self._lock = threading.Lock()

        has_cuda = torch.cuda.is_available()

        if self.gpu_mode == 'persistent' and has_cuda:
            load_device = 'cuda'
        else:
            load_device = 'cpu'

        print(f'Omniparser GPU mode: {self.gpu_mode} (CUDA available: {has_cuda})')

        self.som_model = get_yolo_model(model_path=config['som_model_path'])
        self.caption_model_processor = get_caption_model_processor(
            model_name=config['caption_model_name'],
            model_name_or_path=config['caption_model_path'],
            device=load_device
        )

        # For ondemand mode: keep model as float16 on CPU for fast GPU transfer
        if self.gpu_mode == 'ondemand' and has_cuda:
            model = self.caption_model_processor['model']
            if model.dtype != torch.float16:
                self.caption_model_processor['model'] = model.half()
            # Pin memory for faster PCIe transfers
            for param in self.caption_model_processor['model'].parameters():
                param.data = param.data.pin_memory()
            print(f'Omniparser: ondemand mode, idle timeout: {self.gpu_idle_timeout}s')

        print('Omniparser initialized!!!')

    def _to_gpu(self):
        """Move caption model to GPU."""
        model = self.caption_model_processor['model']
        if model.device.type != 'cuda':
            start = time.time()
            self.caption_model_processor['model'] = model.to('cuda')
            print(f'Omniparser: model moved to GPU in {time.time() - start:.3f}s')

    def _to_cpu(self):
        """Move caption model back to CPU and free VRAM."""
        model = self.caption_model_processor['model']
        if model.device.type != 'cpu':
            self.caption_model_processor['model'] = model.to('cpu')
            torch.cuda.empty_cache()
            print('Omniparser: model offloaded to CPU, VRAM freed')

    def _schedule_offload(self):
        """Schedule GPU offload after idle timeout."""
        if self._offload_timer is not None:
            self._offload_timer.cancel()
        self._offload_timer = threading.Timer(self.gpu_idle_timeout, self._idle_offload)
        self._offload_timer.daemon = True
        self._offload_timer.start()

    def _idle_offload(self):
        """Called by timer — offload if still idle."""
        with self._lock:
            self._to_cpu()

    def parse(self, image_base64: str):
        image_bytes = base64.b64decode(image_base64)
        image = Image.open(io.BytesIO(image_bytes))
        print('image size:', image.size)

        box_overlay_ratio = max(image.size) / 3200
        draw_bbox_config = {
            'text_scale': 0.8 * box_overlay_ratio,
            'text_thickness': max(int(2 * box_overlay_ratio), 1),
            'text_padding': max(int(3 * box_overlay_ratio), 1),
            'thickness': max(int(3 * box_overlay_ratio), 1),
        }

        with self._lock:
            # Move to GPU if in ondemand mode
            if self.gpu_mode == 'ondemand' and torch.cuda.is_available():
                self._to_gpu()

            (text, ocr_bbox), _ = check_ocr_box(image, display_img=False, output_bb_format='xyxy', easyocr_args={'text_threshold': 0.8}, use_paddleocr=False)
            dino_labled_img, label_coordinates, parsed_content_list = get_som_labeled_img(image, self.som_model, BOX_TRESHOLD = self.config['BOX_TRESHOLD'], output_coord_in_ratio=True, ocr_bbox=ocr_bbox,draw_bbox_config=draw_bbox_config, caption_model_processor=self.caption_model_processor, ocr_text=text,use_local_semantics=True, iou_threshold=0.7, scale_img=False, batch_size=int(os.environ.get('OMNIPARSER_BATCH_SIZE', '128')))

            # Schedule offload after idle timeout
            if self.gpu_mode == 'ondemand':
                self._schedule_offload()

        return dino_labled_img, parsed_content_list
