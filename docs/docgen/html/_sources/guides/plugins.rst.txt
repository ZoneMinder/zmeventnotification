Writing your own detection plugin
---------------------------------
It is super simple to create your own plugin.

Your plugin needs to be created as a class that detect.py can import.

The best file to start from is hog.py (simplest)

In general, your plugin needs to follow the following structure:


.. code-block:: python

        class YourPluginName:
                
                # input
                def __init__ (self, param1, ...,paramN):

                # expected output
                # none


                def get_classes(self):
                        # classes is a list of objects your plugin detects
                        # example ['item1', 'item2', 'item3']

                # expected output
                # list of class names


                def detect (self, image):
                        # image passed will be the image to detect
                        # format is that returned by cv2.imread

                # expected output
                # list of (rects, labels, confidence)
                # where:
                #       rects = list of (x1,y1,x2,y2) bounding box of object detected
                #               x1,y1 = left, top coordinates
                #               x2,y2 = right, bottom coordinates
                #       labels = list of object names
                #       conidence = string number between 1 and 0 for confidence



