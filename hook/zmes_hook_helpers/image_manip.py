from configparser import ConfigParser
import zmes_hook_helpers.common_params as g
from shapely.geometry import Polygon
import cv2
import numpy as np
import pickle
import re

# Generic image related algorithms

# once all bounding boxes are detected, we check to see if any of them
# intersect the polygons, if specified
# it also makes sure only patterns specified in detect_pattern are drawn


def processPastDetection (bbox, label, conf,mid):

    try:
        FileNotFoundError
    except NameError:
        FileNotFoundError = IOError

    if not mid:
        g.logger.debug ('Monitor ID not specified, cannot match past detections')
        return bbox, label, conf
    mon_file = g.config['image_path'] + '/monitor-'+mid +'-data.pkl' 
    g.logger.debug ('trying to load '+mon_file) 
    try:
        fh = open(mon_file, "rb")
        saved_bs = pickle.load(fh)
        saved_ls = pickle.load(fh)
        saved_cs = pickle.load(fh)
    except FileNotFoundError:
        g.logger.debug ('No history data file found for monitor {}'.format(mid))
        return bbox, label, conf
    # load past detection 
   
    m = re.match('(\d+)(px|%)?$', g.config['past_det_max_diff_area'],
                 re.IGNORECASE)
    if m:
        max_diff_area = int(m.group(1))
        use_percent = True if m.group(2) is None or m.group(2) == '%' else False
    else:
        g.logger.error('past_det_max_diff_area misformatted: {}'.format(g.config['past_det_max_diff_area']))
        return bbox, label, conf

    # it's very easy to forget to add 'px' when using pixels
    if use_percent and (max_diff_area < 0 or max_diff_area > 100):
        g.logger.error('past_det_max_diff_area must be in the range 0-100 when using percentages: {}'.format(g.config['past_det_max_diff_area']))
        return bbox, label, conf

    #g.logger.debug ('loaded past: bbox={}, labels={}'.format(saved_bs, saved_ls));

    new_label = []
    new_bbox = []
    new_conf = []

    for idx, b in enumerate(bbox): 
        # iterate list of detections
        old_b = b
        it = iter(b)
        b = list(zip(it,it))
        
        b.insert(1, (b[1][0], b[0][1]))
        b.insert(3, (b[0][0], b[1][1]))
        #g.logger.debug ("Past detection: {}@{}".format(saved_ls[idx],b))
        #g.logger.debug ('BOBK={}'.format(b))
        obj = Polygon(b)
        foundMatch = False
        for saved_idx, saved_b in enumerate(saved_bs):
            # compare current detection element with saved list from file
            if saved_ls[saved_idx] != label[idx]: continue
            it = iter(saved_b)
            saved_b = list(zip(it,it))
            saved_b.insert(1,
             (saved_b[1][0], saved_b[0][1]))
            saved_b.insert(3, (saved_b[0][0], saved_b[1][1]))
            saved_obj = Polygon(saved_b)
            max_diff_pixels = max_diff_area
            
            if saved_obj.intersects(obj):
                if obj.contains(saved_obj):
                    diff_area = obj.difference(saved_obj).area
                    if use_percent:
                        max_diff_pixels = obj.area * max_diff_area / 100;
                else:
                    diff_area = saved_obj.difference(obj).area
                    if use_percent:
                        max_diff_pixels = saved_obj.area * max_diff_area / 100;
                
                if diff_area <= max_diff_pixels:
                    g.logger.debug ('past detection {}@{} approximately matches {}@{} removing'.format(saved_ls[saved_idx],saved_b, label[idx],b))
                    foundMatch = True
                    break
        if not foundMatch:
            new_bbox.append(old_b)
            new_label.append(label[idx])
            new_conf.append(conf[idx])

    return new_bbox, new_label, new_conf


def processFilters(bbox, label, conf, match):
    # bbox is the set of bounding boxes
    # labels are set of corresponding object names
    # conf are set of confidence scores (for hog and face this is set to 1)
    # match contains the list of labels that will be allowed based on detect_pattern
    #g.logger.debug ("PROCESS INTERSECTION {} AND {}".format(bbox,label))
    new_label = []
    new_bbox = []
    new_conf = []

    for idx, b in enumerate(bbox):
        if conf[idx] < g.config['yolo_min_confidence']:
            g.logger.info ('object:{} at {} has a lower confidence:{} than min confidence of: {}, ignoring'.format(label[idx], b, conf[idx], g.config['yolo_min_confidence']))
            continue
        else:
            g.logger.info ('object:{} at {} has an acceptable confidence:{} (min confidence={})'.format(label[idx], b, conf[idx], g.config['yolo_min_confidence']))


        doesIntersect = False
        # cv2 rectangle only needs top left and bottom right
        # but to check for polygon intersection, we need all 4 corners
        # b has [a,b,c,d] -> convert to [a,b, c,b, c,d, a,d]
        # https://stackoverflow.com/a/23286299/1361529
        old_b = b
        it = iter(b)
        b = list(zip(it, it))
        #g.logger.debug ("BB={}".format(b))
        #g.logger.debug ("BEFORE INSERT: {}".format(b))
        b.insert(1, (b[1][0], b[0][1]))
        b.insert(3, (b[0][0], b[2][1]))
        g.logger.debug ("intersection: polygon in process={}".format(b))
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
                    g.logger.info ('discarding "{}" as it does not match your filters'.format(label[idx]))
                    g.logger.debug('{} intersects object:{}[{}] but does NOT match your detect_pattern filter of {}'
                                   .format(p['name'], label[idx], b, g.config['detect_pattern']))
                doesIntersect = True
                break
        # out of poly loop
        if not doesIntersect:
            g.logger.info('object:{} at {} does not fall into any polygons, removing...'
                            .format(label[idx], obj))
    #out of object loop
    return new_bbox, new_label, new_conf


def getValidPlateDetections(bbox, label, conf):
    # FIXME: merge this into the function above and do it correctly
    # bbox is the set of bounding boxes
    # labels are set of corresponding object names
    # conf are set of confidence scores 

    if not len(label):
        return bbox, label, conf
    new_label = []
    new_bbox = []
    new_conf = []
    g.logger.debug ('Checking vehicle plates for validity')

    try:
        r = re.compile(g.config['alpr_pattern'])
    except re.error:
        g.logger.error ('invalid pattern {}, using .*'.format(g.config['alpr_pattern']))
        r = re.compile('.*')

    match = list(filter(r.match, label))

    for idx, b in enumerate(bbox):
        if not label[idx] in match:
            g.logger.debug ('discarding plate:{} as it does not match alpr filter pattern:{}'.format(label[idx], g.config['alpr_pattern']))
            continue

        old_b = b
        it = iter(b)
        b = list(zip(it, it))
        #g.logger.debug ("BB={}".format(b))
        b.insert(1, (b[1][0], b[0][1]))
        b.insert(3, (b[0][0], b[2][1]))
        #g.logger.debug ("valid plate: polygon in process={}".format(b))
        obj = Polygon(b)
        doesIntersect = False
        for p in g.polygons:
           # g.logger.debug ("valid plate: mask in process={}".format(p['value']))
            poly = Polygon(p['value'])
            # Lets make sure the license plate doesn't cover the full polygon area
            # if it did, its very likey a bogus reading
            if obj.intersects(poly):
                res = 'Plate:{} at {} intersects polygon:{} at {} '.format(label[idx], obj, p['name'], poly)
                if not obj.contains(poly):
                    res = res + 'but does not contain polgyon, assuming it to be VALID'
                    new_label.append(label[idx])
                    new_bbox.append(old_b)
                    new_conf.append(conf[idx])
                    doesIntersect = True
                else:
                    res = res + 'but also contains polygon, assuming it to be INVALID'
                g.logger.debug(res)
                if doesIntersect: break
        # out of poly loop
        if not doesIntersect:
            g.logger.debug('plate:{} at {} does not fall into any polygons, removing...'.format(label[idx], obj))
    #out of object loop
    return new_bbox, new_label, new_conf


# draws bounding boxes of identified objects and polygons

def draw_bbox(img, bbox, labels, classes, confidence, color=None, write_conf=True):

   # g.logger.debug ("DRAW BBOX={} LAB={}".format(bbox,labels))
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
        #=g.logger.debug ('drawing box for: {}'.format(label))
        color = bgr_slate_colors[i % arr_len]
        if write_conf and confidence:
            label += ' ' + str(format(confidence[i] * 100, '.2f')) + '%'
        # draw bounding box around object
        
        #g.logger.debug ("DRAWING RECT={},{} {},{}".format(bbox[i][0], bbox[i][1],bbox[i][2], bbox[i][3]))
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


