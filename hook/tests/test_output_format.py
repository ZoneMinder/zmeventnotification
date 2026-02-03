"""Tests for the --SPLIT-- output format contract between zm_detect.py (Python) and the Perl ES consumer.

These tests validate the output format without running the actual detection pipeline.
"""
import json
import pytest


def build_detection_output(prefix, labels, boxes, frame_id, confidences, image_dimensions=None):
    """Simulate the output formatting logic from zm_detect.py main_handler()."""
    seen = {}
    pred = ""
    for idx, l in enumerate(labels):
        if l not in seen:
            label_txt = l + ","
            pred = pred + label_txt
            seen[l] = 1

    if pred:
        pred = pred.rstrip(",")
        pred = prefix + "detected:" + pred

    obj_json = {
        "labels": labels,
        "boxes": boxes,
        "frame_id": frame_id,
        "confidences": confidences,
        "image_dimensions": image_dimensions,
    }

    if pred:
        return pred + "--SPLIT--" + json.dumps(obj_json)
    return ""


class TestOutputFormat:
    def test_single_detection(self):
        output = build_detection_output(
            "[a] ", ["person"], [[100, 200, 300, 400]], "alarm", [0.95]
        )
        assert "--SPLIT--" in output
        txt, json_str = output.split("--SPLIT--", 1)
        assert txt == "[a] detected:person"
        data = json.loads(json_str)
        assert data["labels"] == ["person"]
        assert data["frame_id"] == "alarm"

    def test_multiple_detections(self):
        output = build_detection_output(
            "[a] ",
            ["person", "car"],
            [[100, 200, 300, 400], [10, 20, 30, 40]],
            "alarm",
            [0.95, 0.87],
        )
        txt, json_str = output.split("--SPLIT--", 1)
        assert "person" in txt
        assert "car" in txt
        data = json.loads(json_str)
        assert len(data["labels"]) == 2

    def test_snapshot_frame(self):
        output = build_detection_output(
            "[s] ", ["dog"], [[0, 0, 100, 100]], "snapshot", [0.80]
        )
        txt, json_str = output.split("--SPLIT--", 1)
        assert txt.startswith("[s]")
        data = json.loads(json_str)
        assert data["frame_id"] == "snapshot"

    def test_no_detections(self):
        output = build_detection_output("[a] ", [], [], "alarm", [])
        assert output == ""

    def test_duplicate_labels_deduped(self):
        output = build_detection_output(
            "[a] ",
            ["person", "person", "car"],
            [[1, 2, 3, 4], [5, 6, 7, 8], [9, 10, 11, 12]],
            "alarm",
            [0.9, 0.8, 0.7],
        )
        txt, _ = output.split("--SPLIT--", 1)
        # 'person' should appear only once in the text
        assert txt.count("person") == 1

    def test_json_has_required_keys(self):
        output = build_detection_output(
            "[a] ", ["person"], [[0, 0, 1, 1]], "alarm", [0.99]
        )
        _, json_str = output.split("--SPLIT--", 1)
        data = json.loads(json_str)
        for key in ("labels", "boxes", "frame_id", "confidences", "image_dimensions"):
            assert key in data, f"Missing key: {key}"

    def test_special_chars_in_label(self):
        output = build_detection_output(
            "[a] ", ["person (hat)"], [[0, 0, 1, 1]], "alarm", [0.75]
        )
        txt, json_str = output.split("--SPLIT--", 1)
        assert "person (hat)" in txt
        data = json.loads(json_str)
        assert data["labels"][0] == "person (hat)"

    def test_unknown_frame_prefix(self):
        output = build_detection_output(
            "[x] ", ["cat"], [[0, 0, 50, 50]], "12345", [0.6]
        )
        txt, _ = output.split("--SPLIT--", 1)
        assert txt.startswith("[x]")
