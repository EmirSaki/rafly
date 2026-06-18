import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

class FullScreenImagePage extends StatefulWidget {
  final String? imageBase64;
  final List<String>? imageList;
  final String title;
  final int initialIndex;

  const FullScreenImagePage({
    super.key,
    this.imageBase64,
    this.imageList,
    required this.title,
    this.initialIndex = 0,
  });

  @override
  State<FullScreenImagePage> createState() => _FullScreenImagePageState();
}

class _FullScreenImagePageState extends State<FullScreenImagePage> {
  late final PageController _pageController;
  late int _currentPage;
  late final List<String> _images;

  @override
  void initState() {
    super.initState();
    if (widget.imageList != null && widget.imageList!.isNotEmpty) {
      _images = widget.imageList!;
    } else if (widget.imageBase64 != null && widget.imageBase64!.isNotEmpty) {
      _images = [widget.imageBase64!];
    } else {
      _images = [];
    }
    _currentPage = widget.initialIndex.clamp(0, _images.isEmpty ? 0 : _images.length - 1);
    _pageController = PageController(initialPage: _currentPage);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Uint8List? _decodeImage(String raw) {
    try {
      String data = raw;
      if (data.contains(',')) {
        data = data.split(',').last;
      }
      return Uint8List.fromList(base64Decode(data));
    } catch (_) {
      return null;
    }
  }

  Widget _buildImage(String imageData) {
    if (imageData.startsWith('data:') || !imageData.startsWith('http')) {
      final bytes = _decodeImage(imageData);
      if (bytes != null) {
        return InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            width: double.infinity,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image,
              color: Colors.white54,
              size: 64,
            ),
          ),
        );
      }
    } else {
      return InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Image.network(
          imageData,
          fit: BoxFit.contain,
          width: double.infinity,
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image,
            color: Colors.white54,
            size: 64,
          ),
        ),
      );
    }

    return const Icon(Icons.broken_image, color: Colors.white54, size: 64);
  }

  @override
  Widget build(BuildContext context) {
    final hasMultiple = _images.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          hasMultiple
              ? '${widget.title} (${_currentPage + 1}/${_images.length})'
              : widget.title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: _images.isEmpty
          ? const Center(
              child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
            )
          : Stack(
              children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: _images.length,
                  onPageChanged: (i) => setState(() => _currentPage = i),
                  itemBuilder: (_, i) => Center(child: _buildImage(_images[i])),
                ),
                if (hasMultiple)
                  Positioned(
                    bottom: 24,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_images.length, (i) {
                        final isActive = i == _currentPage;
                        return Container(
                          width: isActive ? 10 : 7,
                          height: isActive ? 10 : 7,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isActive ? Colors.white : Colors.white38,
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            ),
    );
  }
}
