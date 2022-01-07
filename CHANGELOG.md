## 0.0.3
### The per label overrides for filters (max_detection_size, min_confidence, contained_area, past_det_max_diff_area) have 2 options to be enabled:
1. Enable in `ml_sequence`: `<MODEL>`: `<SEQUENCE>` - This will apply the config to the specific sequence. **This takes precedence.**
```yaml
ml_sequence:
 object:
    general:
      object_detection_pattern: '{{object_detection_pattern}}'
      same_model_sequence_strategy: '{{same_model_sequence_strategy}}'
    sequence:
      - name: 'DarkNet::v4 Pre-Trained'
        object_config: '{{yolo4_object_config}}'
        object_weights: '{{yolo4_object_weights}}'
        object_labels: '{{yolo4_object_labels}}'
        object_framework: '{{yolo4_object_framework}}'
        object_processor: '{{yolo4_object_processor}}'
        gpu_max_processes: '{{gpu_max_processes}}'
        gpu_max_lock_wait: '{{gpu_max_lock_wait}}'
        cpu_max_processes: '{{cpu_max_processes}}'
        cpu_max_lock_wait: '{{cpu_max_lock_wait}}'
        fp16_target: '{{fp16_target}}'  # only applies to GPU, default is FP32
        show_models: '{{show_models}}'  # at current moment this is a global setting turned on by just setting it to : yes
    
        object_min_confidence: '{{object_min_confidence}}'
        max_detection_size: '{{max_detection_size}}'
        contained_area: '{{contained_area}}'
    
        person_max_detection_size: '{{person_max_detection_size}}'
        person_min_confidence: '{{person_min_confidence}}'
        person_past_det_max_diff_area: '{{person_past_det_max_diff_area}}'
        person_contained_area: '{{person_contained_area}}'
```
2. Enable in `ml_sequence`: `<MODEL>`: `general` - This will apply the config to all sequences in the model
```yaml
ml_sequence:
  object:
    general:
      object_detection_pattern: '{{object_detection_pattern}}'
      same_model_sequence_strategy: '{{same_model_sequence_strategy}}'
      contained_area: '{{contained_area}}'
      person_contained_area: '{{person_contained_area}}'
      max_detection_size: '{{max_detection_size}}'
      person_max_detection_size: '{{person_max_detection_size}}'    
```
### You can break up the mlapi or hooks config files into sections for easier editing
- Previously all the keys were at the base level, but now you can break them up into sections.
```yaml
base_data_path: /blah/blah
sanitize_logs: yes
xxx: 1
yyy: 2

monitors:
  1:
    ccc: 1
```
- To Enable sections you must put `MLAPI: 1` or `ZMES: 1` as the first key in the config file and then put all your keys in sections as you see fit. The sections are removed and all keys are put at the base level when processing, this is just for ease of editing or finding keys.
- You can have as many sections as you want BUT DO NOT nest sections.
```yaml
# Enable sections
MLAPI: 1
# create a general section and put some keys in it
general:
  base_data_path: /blah/blah
  sanitize_logs: yes
  xxx: 1
  yyy: 2


# DO NOT put monitors into a section as it is already setup as its own section
monitors:
  1:
    ccc: 1

# create a section for stream and ml sequences
sequences:
  stream_sequence:
    yyy: 2
  ml_sequence:
    xxx: 2

```


