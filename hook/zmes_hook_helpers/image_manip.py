from configparser import ConfigParser
import zmes_hook_helpers.common_params as g
from shapely.geometry import Polygon
import cv2
import numpy as np

# Generic image related algorithms

# once all bounding boxes are detected, we check to see if any of them
# intersect the polygons, if specified
# it also makes sure only patterns specified in detect_pattern are drawn


def processIntersection(bbox, label, conf, match):

    # bbox is the set of bounding boxes
    # labels are set of corresponding object names
    # conf are set of confidence scores (for hog and face this is set to 1)
    # match contains the list of labels that will be allowed based on detect_pattern

    new_label = []
    new_bbox = []
    new_conf = []

    for idx, b in enumerate(bbox):
        doesIntersect = False
        # cv2 rectangle only needs top left and bottom right
        # but to check for polygon intersection, we need all 4 corners
        # b has [a,b,c,d] -> convert to [a,b, c,b, c,d, a,d]
        # https://stackoverflow.com/a/23286299/1361529
        old_b = b
        it = iter(b)
        b = list(zip(it, it))
        b.insert(1, (b[1][0], b[0][1]))
        b.insert(3, (b[0][0], b[1][1]))
        obj = Polygon(b)

        for p in g.polygons:
            poly = Polygon(p['value'])
            if obj.intersects(poly):
                if label[idx] in match:
                    g.logger.debug('{} intersects object:{}[{}]'.format(p['name'], label[idx], b))
                    new_label.append(label[idx])
                    new_bbox.append(old_b)
                    new_conf.append(conf[idx])
                else:
                    g.logger.debug('{} intersects object:{}[{}] but does NOT match your detect_pattern filter of {}'
                                   .format(p['name'], label[idx], b, g.config['detect_pattern']))
                doesIntersect = True
                break

            else:  # of poly intersects
                g.logger.debug('object:{} at {} does not fall into any polygons, removing...'
                               .format(label[idx], obj))
    return new_bbox, new_label, new_conf


# draws bounding boxes of identified objects and polygons

def draw_bbox(img, bbox, labels, classes, confidence, color=None, write_conf=False):

    slate_colors = [ 
            (39, 174, 96),
            (142, 68, 173),
            (0,129,254),
            (254,60,113),
            (243,134,48),
            (91,177,47)
        ]
    # if no color is specified, use my own slate
    if color is None:
            # opencv is BGR
        bgr_slate_colors = slate_colors[::-1]

    polycolor = g.config['poly_color']
    # first draw the polygons, if any
    newh, neww = img.shape[:2]
    for ps in g.polygons:
        cv2.polylines(img, [np.asarray(ps['value'])], True, polycolor, thickness=2)

    # now draw object boundaries

    arr_len = len(bgr_slate_colors)
    for i, label in enumerate(labels):
        #g.logger.debug ('drawing box for: {}'.format(label))
        color = bgr_slate_colors[i % arr_len]
        if write_conf and confidence:
            label += ' ' + str(format(confidence[i] * 100, '.2f')) + '%'
        # draw bounding box around object
        cv2.rectangle(img, (bbox[i][0], bbox[i][1]), (bbox[i][2], bbox[i][3]), color, 2)

        # write text 
        font_scale = 0.8
        font_type = cv2.FONT_HERSHEY_SIMPLEX
        font_thickness = 1
        #cv2.getTextSize(text, font, font_scale, thickness)
        text_size = cv2.getTextSize(label, font_type, font_scale , font_thickness)[0]
        text_width_padded = text_size[0] + 4
        text_height_padded = text_size[1] + 4

        r_top_left = (bbox[i][0], bbox[i][1] - text_height_padded)
        r_bottom_right = (bbox[i][0] + text_width_padded, bbox[i][1])
        cv2.rectangle(img, r_top_left, r_bottom_right, color, -1)
        #cv2.putText(image, text, (x, y), font, font_scale, color, thickness) 
        # location of text is botom left
        cv2.putText(img, label, (bbox[i][0] + 2, bbox[i][1] - 2), font_type, font_scale, [255, 255, 255], font_thickness)

    return img


