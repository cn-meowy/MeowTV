import 'package:flutter/material.dart';

/// 包装 ListTile 的辅助组件，解决 ListTile 在带背景色的
/// DecoratedBox（如 showModalBottomSheet 的 backgroundColor、
/// Container 的 BoxDecoration）中 ink splash 不可见的问题。
///
/// ListTile 会在最近的 Material 祖先上绘制背景和 ink 效果，
/// 当中间存在带背景色的 DecoratedBox 时会遮挡这些效果。
/// 此组件在 ListTile 外层包裹透明 Material，使 ink 效果可见。
///
/// 用法：将 ListTile 替换为 InkListTile，参数与 ListTile 完全一致。
class InkListTile extends StatelessWidget {
  const InkListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.contentPadding,
    this.onTap,
    this.enabled = true,
    this.dense,
    this.selected = false,
    this.selectedColor,
    this.iconColor,
    this.textColor,
    this.minVerticalPadding,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final EdgeInsetsGeometry? contentPadding;
  final VoidCallback? onTap;
  final bool enabled;
  final bool? dense;
  final bool selected;
  final Color? selectedColor;
  final Color? iconColor;
  final Color? textColor;
  final double? minVerticalPadding;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: ListTile(
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        contentPadding: contentPadding,
        onTap: onTap,
        enabled: enabled,
        dense: dense,
        selected: selected,
        selectedColor: selectedColor,
        iconColor: iconColor,
        textColor: textColor,
        minVerticalPadding: minVerticalPadding,
      ),
    );
  }
}

/// 包装 SwitchListTile 的辅助组件，解决与 InkListTile 相同的
/// DecoratedBox 遮挡 ink splash 问题。
///
/// SwitchListTile 继承自 ListTile，同样会在最近的 Material 祖先上
/// 绘制背景和 ink 效果。当被带背景色的 Container 包裹时，
/// 需要在外层添加透明 Material。
///
/// 用法：将 SwitchListTile 替换为 InkSwitchListTile。
class InkSwitchListTile extends StatelessWidget {
  const InkSwitchListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.activeThumbColor,
    this.activeTrackColor,
    this.inactiveThumbColor,
    this.inactiveTrackColor,
    this.thumbIcon,
    this.dense = false,
    this.contentPadding,
    this.controlAffinity,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final Color? activeThumbColor;
  final Color? activeTrackColor;
  final Color? inactiveThumbColor;
  final Color? inactiveTrackColor;
  final WidgetStateProperty<Icon?>? thumbIcon;
  final bool dense;
  final EdgeInsetsGeometry? contentPadding;
  final ListTileControlAffinity? controlAffinity;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
        secondary: secondary,
        activeThumbColor: activeThumbColor,
        activeTrackColor: activeTrackColor,
        inactiveThumbColor: inactiveThumbColor,
        inactiveTrackColor: inactiveTrackColor,
        thumbIcon: thumbIcon,
        dense: dense,
        contentPadding: contentPadding,
        controlAffinity: controlAffinity,
      ),
    );
  }
}

/// 包装 CheckboxListTile 的辅助组件，解决与 InkListTile 相同的
/// DecoratedBox 遮挡 ink splash 问题。
///
/// CheckboxListTile 继承自 ListTile，同样会在最近的 Material 祖先上
/// 绘制背景和 ink 效果。当被带背景色的 Container 包裹时，
/// 需要在外层添加透明 Material。
///
/// 用法：将 CheckboxListTile 替换为 InkCheckboxListTile。
class InkCheckboxListTile extends StatelessWidget {
  const InkCheckboxListTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.title,
    this.subtitle,
    this.secondary,
    this.activeColor,
    this.checkColor,
    this.hoverColor,
    this.dense,
    this.contentPadding,
    this.controlAffinity,
    this.tristate = false,
    this.shape,
    this.side,
  });

  final bool? value;
  final ValueChanged<bool?>? onChanged;
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final Color? activeColor;
  final Color? checkColor;
  final Color? hoverColor;
  final bool? dense;
  final EdgeInsetsGeometry? contentPadding;
  final ListTileControlAffinity? controlAffinity;
  final bool tristate;
  final OutlinedBorder? shape;
  final BorderSide? side;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: CheckboxListTile(
        value: value,
        onChanged: onChanged,
        title: title,
        subtitle: subtitle,
        secondary: secondary,
        activeColor: activeColor,
        checkColor: checkColor,
        hoverColor: hoverColor,
        dense: dense,
        contentPadding: contentPadding,
        controlAffinity: controlAffinity,
        tristate: tristate,
        shape: shape,
        side: side,
      ),
    );
  }
}
