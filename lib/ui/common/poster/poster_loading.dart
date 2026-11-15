import 'package:flutter/material.dart';
import 'package:ticketbox/ui/theme/constants.dart';

class PosterLoading extends StatelessWidget {
  const PosterLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: PosterConstants.aspectRationWhenNoTitle,
          child: Center(
            child: Container(
              margin: GeneralMarginConstants.zeroMargin,
              alignment: Alignment.center,
              color: Colors.black.withOpacity(0.4),
              child: const CircularProgressIndicator(),
            ),
          ),
        ),
      ],
    );
  }
}

class PosterLoadingWithTitle extends StatelessWidget {
  const PosterLoadingWithTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: PosterConstants.aspectRationWhenTitle,
          child: Center(
            child: Container(
              margin: GeneralMarginConstants.zeroMargin,
              alignment: Alignment.center,
              color: Colors.black.withOpacity(0.4),
              child: const CircularProgressIndicator(),
            ),
          ),
        ),
        Container(
          key: const ValueKey('title_placeholder'),
          margin: PosterConstants.titleMargin,
          child: const Text(' ', style: TextStyle(fontSize: 12), maxLines: 1, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class PosterLoadingWithTitleAndSubtitle extends StatelessWidget {
  const PosterLoadingWithTitleAndSubtitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: PosterConstants.aspectRationWhenTitleAndSubtitle,
          child: Center(
            child: Container(
              margin: GeneralMarginConstants.zeroMargin,
              alignment: Alignment.center,
              color: Colors.black.withOpacity(0.4),
              child: const CircularProgressIndicator(),
            ),
          ),
        ),
        Container(
          key: const ValueKey('title_placeholder'),
          margin: PosterConstants.titleMargin,
          child: const Text(' ', style: TextStyle(fontSize: 12), maxLines: 1, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
        ),
        Container(
          key: const ValueKey('sub_title_placeholder'),
          margin: PosterConstants.subTitleMargin,
          child: Builder(
            builder: (context) {
              return const Text(
                ' ',
                style: TextStyle(fontSize: 11),
                maxLines: 1,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              );
            },
          ),
        ),
      ],
    );
  }
}
