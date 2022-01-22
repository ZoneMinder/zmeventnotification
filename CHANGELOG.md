# Versioning will start at 7.0.0 if NEO is accepted for master.
1. zmNinja complains if zmeventnotfifcation.pl is below 6.0.0. I would prefer 0.0.0 as it is actively being developed and changing drastically.
2. All INI configs are now parsed using YAML.
3. New tool included to convert zmeventnotification.ini and secrets.ini to the yaml format. Users existing objectconfig.ini will need to be converted by the user into the new formats by following the example config provided.
# Please be aware that 7.0.x will be the new development version.
- Things may break or unexpected results may occur. **Please report any issues you find.**
- I have tried to have users test my code base without much success, be aware that the testing so far is only my personal testing.
## 7.0.4
### The way that the config files are processed has been changed
- To allow reevaluation of keys that were not in the base config. If you do not have `car_past_det_max_diff_size` configured in the BASE keys but have it inside a per monitor override, the key will be added to the base config and updated across the per-monitor cached configs! 

### The per label overrides for filters (max_detection_size, min_confidence, contained_area, past_det_max_diff_area) have 2 options to be enabled:
1. Enable in `ml_sequence`: `<MODEL>`: `<SEQUENCE>` - This will apply the config to the specific sequence. **This method takes precedence over placing options in 'general'.**
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
2. Enable in `ml_sequence`: `general` - This will apply the config to all sequences in all model
```yaml
ml_sequence:
  general:
    same_model_sequence_strategy: '{{same_model_sequence_strategy}}'
    contained_area: '{{contained_area}}'
    person_contained_area: '{{person_contained_area}}'
    max_detection_size: '{{max_detection_size}}'
    person_max_detection_size: '{{person_max_detection_size}}'    
```
### You can break up the mlapi or hooks config files into sections for easier editing
- Previously all the keys were at the base level, but now you can break them up into sections.
```yaml
# LEGACY FORMATTING
base_data_path: /blah/blah
sanitize_logs: yes
xxx: 1
yyy: 2

monitors:
  1:
    ccc: 1
```
- To Enable sections you must put `MLAPI: 1` or `ZMES: 1` as the first key in the config file and then put all your keys in sections as you see fit. The sections are removed and all keys are put at the base level when processing, this is just for ease of editing or finding keys.
- All section names MUST BE UNIQUE!
- You can have as many sections as you want BUT DO NOT nest sections.
- Do not nest the `monitors` section as technically it is already in its own section already!
```yaml
# Enable sections
MLAPI: 1
# create a general section and put some keys in it (Note: the name of the scetion is unimportant BUT MUST BE unique)
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

## 7.0.0
- `contained_area` and `<LABEL>_contained_area` filter added, this calculates the area of the objects bounding box that is inside a polygon zone. If the object does not have X pixels or X % of its area inside the zone it will not be considered a hit.
- YAML for all configuration and secrets files replacing the INI format, YAML is parsed safely to sanitize user input.