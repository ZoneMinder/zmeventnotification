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

def draw_bbox(img, bbox, labels, classes, confidence, colors=None, write_conf=False ):

    COLORS = np.random.uniform(0, 255, size=(80, 3))
    polycolor = g.config['poly_color']
    # first draw the polygons, if any
    for ps in g.polygons:
        cv2.polylines(img, [np.asarray(ps['value'])], True, polycolor, thickness=2)

    # now draw object boundaries

    for i, label in enumerate(labels):
        if colors is None:
            color = COLORS[classes.index(label)]
        else:
            color = colors[classes.index(label)]

        if write_conf and confidence:
            label += ' ' + str(format(confidence[i] * 100, '.2f')) + '%'
        cv2.rectangle(img, (bbox[i][0], bbox[i][1]), (bbox[i][2], bbox[i][3]), color, 2)
        cv2.putText(img, label, (bbox[i][0], bbox[i][1] - 10), cv2.FONT_HERSHEY_SIMPLEX, 0.5, color, 2)
    return img


