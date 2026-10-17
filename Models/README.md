# Bundled image classifier

MobileNetV2FP16 is a pretrained general image classifier distributed through Apple's Core ML model gallery. Nature Relay uses its original weights for offline photo suggestions; it does not train a new model or make species identification claims.

- Model gallery: https://developer.apple.com/machine-learning/models/
- Original download: https://ml-assets.apple.com/coreml/models/Image/ImageClassification/MobileNetV2/MobileNetV2FP16.mlmodel
- Model source noted in its metadata: https://github.com/tensorflow/models/tree/master/research/slim/nets/mobilenet
- Authors noted in its metadata: Mark Sandler, Andrew Howard, Menglong Zhu, Andrey Zhmoginov, Liang-Chieh Chen.
- TensorFlow license text is preserved in `TENSORFLOW-LICENSE.txt`, retrieved from https://github.com/tensorflow/tensorflow/blob/master/LICENSE as directed by model metadata.

The app bundles the compiled `NatureRelay/MobileNetV2FP16.mlmodelc` directory. The original download URL above is recorded for provenance; the uncompiled model is not duplicated in this checkout. To regenerate, download the unchanged model to `Models/MobileNetV2FP16.mlmodel`, then run:

```sh
xcrun coremlcompiler compile MobileNetV2FP16.mlmodel ../NatureRelay
```

Labels and confidence are suggestions. The sample poppy photo receives the label `daisy`, which maps to the broad `flower` category; this is useful for choosing a character category, and does not prove the exact flower species. Low-confidence suggestions require user review.
